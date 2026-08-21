import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host.dart';
import '../models/known_host.dart';

class StorageService {
  static const _hostsKey = 'yourssh.hosts';

  /// macOS deliberately uses the *legacy file* Keychain.
  /// `flutter_secure_storage` defaults to the data-protection Keychain, which
  /// requires an entitlement carrying a keychain access group — a restricted
  /// entitlement no ad-hoc-signed binary can hold, so every `SecItemAdd`
  /// returned `-34018` (`errSecMissingEntitlement`) and each secret silently
  /// took the `SharedPreferences` fallback and landed in
  /// `~/Library/Preferences/<bundle-id>.plist` as readable text (issue #91).
  /// The legacy Keychain accepts the same items with no entitlement on this
  /// unsandboxed build. Changing the ad-hoc signature between versions can
  /// make macOS re-prompt for access to items the previous build wrote.
  @visibleForTesting
  static const macOsKeychainOptions = MacOsOptions(
    accountName: 'yourssh',
    useDataProtectionKeyChain: false,
  );

  static const _storage = FlutterSecureStorage(
    mOptions: macOsKeychainOptions,
    wOptions: WindowsOptions(),
  );

  /// Secrets whose latest write had to fall back to cleartext
  /// `SharedPreferences` because the platform secure store refused. Surfaced
  /// in Settings → Security so the downgrade is visible instead of being just
  /// a `debugPrint` (issue #91).
  final _plaintextKeys = <String>{};

  /// Bumped whenever [plaintextSecretKeys] changes, so the UI can rebuild.
  final ValueNotifier<int> secretStorageRevision = ValueNotifier(0);

  Set<String> get plaintextSecretKeys => Set.unmodifiable(_plaintextKeys);

  bool get hasPlaintextSecrets => _plaintextKeys.isNotEmpty;

  /// Fires the first time a secret has to be written in cleartext, so the
  /// caller can raise a notification. Not called again for the same key.
  void Function(String key, Object error)? onPlaintextFallback;

  void _markPlaintext(String key, Object error) {
    if (_plaintextKeys.add(key)) {
      secretStorageRevision.value++;
      onPlaintextFallback?.call(key, error);
    }
  }

  void _clearPlaintext(String key) {
    if (_plaintextKeys.remove(key)) secretStorageRevision.value++;
  }

  // ── Hosts ──────────────────────────────────────────────

  Future<List<Host>> loadHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Host.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveHosts(List<Host> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostsKey, jsonEncode(hosts.map((h) => h.toJson()).toList()));
  }

  // ── Credentials (Keychain / Credential Manager) ────────
  // Strategy: write to secure storage FIRST. Only fall back to SharedPreferences
  // if secure storage throws. On successful secure write, purge any stale
  // plaintext copy in SharedPreferences (e.g., left from a prior fallback).

  Future<void> _saveSecret(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(key)) await prefs.remove(key);
      _clearPlaintext(key);
    } catch (e) {
      debugPrint('[StorageService] secure write failed for $key, falling back to prefs: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      _markPlaintext(key, e);
    }
  }

  Future<String?> _loadSecret(String key) async {
    try {
      final val = await _storage.read(key: key);
      if (val != null) return val;
    } catch (e) {
      debugPrint('[StorageService] secure read failed for $key: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _deleteSecret(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[StorageService] secure delete failed for $key: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    _clearPlaintext(key);
  }

  Future<void> savePassword(String hostId, String password) =>
      _saveSecret('pw_$hostId', password);

  Future<String?> loadPassword(String hostId) => _loadSecret('pw_$hostId');

  Future<void> deletePassword(String hostId) => _deleteSecret('pw_$hostId');

  /// Sudo password for elevated SFTP (SftpMode.sudo / custom). Stored with
  /// the same secure-first strategy as host passwords; never synced.
  Future<void> saveSudoPassword(String hostId, String password) =>
      _saveSecret('sudopw_$hostId', password);

  Future<String?> loadSudoPassword(String hostId) =>
      _loadSecret('sudopw_$hostId');

  Future<void> deleteSudoPassword(String hostId) =>
      _deleteSecret('sudopw_$hostId');

  Future<void> savePassphrase(String keyId, String passphrase) =>
      _saveSecret('pp_$keyId', passphrase);

  Future<String?> loadPassphrase(String keyId) => _loadSecret('pp_$keyId');

  /// Generic secret store for app-scoped secrets (e.g., sync passphrase).
  /// Caller is responsible for key namespacing.
  Future<void> saveGenericSecret(String key, String value) =>
      _saveSecret(key, value);

  Future<String?> loadGenericSecret(String key) => _loadSecret(key);

  Future<void> deleteGenericSecret(String key) => _deleteSecret(key);

  // ── Plaintext-secret carry-over (issue #91) ────────────────

  /// Prefixes of the prefs keys that hold per-host / per-key secrets.
  static const _secretKeyPrefixes = ['pw_', 'sudopw_', 'pp_'];

  /// App-scoped secret keys that carry no prefix.
  static const _secretKeys = {'sync_passphrase'};

  /// Whether [key] (a SharedPreferences key) names a secret that belongs in
  /// the platform secure store rather than prefs.
  @visibleForTesting
  static bool isSecretPrefsKey(String key) =>
      _secretKeys.contains(key) || _secretKeyPrefixes.any(key.startsWith);

  /// Moves secrets that earlier releases wrote to SharedPreferences in
  /// cleartext into the secure store (issue #91).
  ///
  /// Each key is written, **read back to confirm it took**, and only then
  /// removed from prefs — a failed write must never destroy the only copy of
  /// a password. Keys that cannot be moved stay where they are and are
  /// reported through [plaintextSecretKeys], so a later launch retries them.
  ///
  /// Safe to call on every startup: with no secrets left in prefs it is a
  /// single `getKeys()` scan. Returns the number of secrets moved and never
  /// throws.
  Future<int> migratePlaintextSecrets() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(isSecretPrefsKey).toList();
    var moved = 0;
    for (final key in keys) {
      try {
        final value = prefs.getString(key);
        if (value == null) continue;
        // The secure store wins in _loadSecret, so a value already there is
        // authoritative — drop the stale prefs copy without rewriting it.
        // Also closes the race against a concurrent save of the same key.
        if (await _storage.read(key: key) == null) {
          await _storage.write(key: key, value: value);
          if (await _storage.read(key: key) != value) {
            throw StateError('secure store read-back mismatch');
          }
        }
        await prefs.remove(key);
        _clearPlaintext(key);
        moved++;
      } catch (e) {
        debugPrint(
            '[StorageService] could not move $key into the secure store: $e');
        _markPlaintext(key, e);
      }
    }
    return moved;
  }

  // ── Known Hosts ────────────────────────────────────────────

  static const _knownHostsKey = 'yourssh.known_hosts';

  Future<List<KnownHost>> loadKnownHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_knownHostsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => KnownHost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveKnownHosts(List<KnownHost> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _knownHostsKey, jsonEncode(hosts.map((h) => h.toJson()).toList()));
  }

  // ── Pinned Groups ──────────────────────────────────────────

  static const _pinnedGroupsKey = 'yourssh.pinned_groups';

  Future<List<String>> loadPinnedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_pinnedGroupsKey) ?? [];
  }

  Future<void> savePinnedGroups(List<String> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedGroupsKey, groups);
  }
}
