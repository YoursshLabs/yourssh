import 'package:flutter/foundation.dart';
import '../models/known_host.dart';
import '../services/storage_service.dart';

class KnownHostsProvider extends ChangeNotifier {
  final StorageService? _storage;
  List<KnownHost> _hosts;
  HostKeyChallenge? _pendingChallenge;

  KnownHostsProvider(StorageService storage)
      : _storage = storage,
        _hosts = [];

  // For unit tests only — no storage, pre-loaded hosts.
  KnownHostsProvider.forTest(List<KnownHost> initial)
      : _storage = null,
        _hosts = List.of(initial);

  List<KnownHost> get hosts => List.unmodifiable(_hosts);
  HostKeyChallenge? get pendingChallenge => _pendingChallenge;

  Future<void> load() async {
    if (_storage == null) return;
    _hosts = await _storage.loadKnownHosts();
    notifyListeners();
  }

  Future<void> remove(KnownHost entry) async {
    _hosts.removeWhere((h) =>
        h.host == entry.host && h.port == entry.port && h.keyType == entry.keyType);
    await _storage?.saveKnownHosts(_hosts);
    notifyListeners();
  }

  Future<bool> verifyHostKey(
      String host, int port, String keyType, Uint8List fingerprint) async {
    final fp = KnownHost.bytesToFingerprint(fingerprint);
    final existing = _hosts
        .where((h) => h.host == host && h.port == port && h.keyType == keyType)
        .firstOrNull;

    if (existing == null) {
      _hosts.add(KnownHost(
          host: host,
          port: port,
          keyType: keyType,
          fingerprint: fp,
          addedAt: DateTime.now()));
      await _storage?.saveKnownHosts(_hosts);
      notifyListeners();
      return true;
    }

    if (existing.fingerprint == fp) return true;

    // Key mismatch — raise challenge; block until UI resolves it.
    // If a previous challenge is still pending (UI dialog stuck), reject it so
    // the prior caller doesn't hang forever and gets a clear "rejected" answer.
    _pendingChallenge?.reject();

    final challenge = HostKeyChallenge(
      host: host,
      port: port,
      keyType: keyType,
      oldFingerprint: existing.fingerprint,
      newFingerprint: fp,
    );
    _pendingChallenge = challenge;
    notifyListeners();

    final trusted = await challenge.result;
    // Only clear if it's still ours — a newer challenge may have replaced us.
    if (identical(_pendingChallenge, challenge)) _pendingChallenge = null;

    if (trusted) {
      _hosts.removeWhere(
          (h) => h.host == host && h.port == port && h.keyType == keyType);
      _hosts.add(KnownHost(
          host: host,
          port: port,
          keyType: keyType,
          fingerprint: fp,
          addedAt: DateTime.now()));
      await _storage?.saveKnownHosts(_hosts);
    }

    notifyListeners();
    return trusted;
  }
}
