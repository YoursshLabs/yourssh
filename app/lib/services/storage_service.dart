import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host.dart';
import '../models/known_host.dart';

class StorageService {
  static const _hostsKey = 'yourssh.hosts';
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(accountName: 'yourssh'),
    wOptions: WindowsOptions(),
  );

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
    } catch (e) {
      debugPrint('[StorageService] secure write failed for $key, falling back to prefs: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
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
