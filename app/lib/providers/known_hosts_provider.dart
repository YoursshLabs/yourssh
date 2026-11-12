import 'package:flutter/foundation.dart';
import '../models/known_host.dart';
import '../services/storage_service.dart';

export '../models/known_host.dart' show RdpCertVerdict, RdpCertChallenge;

class KnownHostsProvider extends ChangeNotifier {
  final StorageService? _storage;
  List<KnownHost> _hosts;
  HostKeyChallenge? _pendingChallenge;
  RdpCertChallenge? _pendingRdpChallenge;

  KnownHostsProvider(StorageService storage)
      : _storage = storage,
        _hosts = [];

  // For unit tests only — no storage, pre-loaded hosts.
  KnownHostsProvider.forTest(List<KnownHost> initial)
      : _storage = null,
        _hosts = List.of(initial);

  List<KnownHost> get hosts => List.unmodifiable(_hosts);
  HostKeyChallenge? get pendingChallenge => _pendingChallenge;
  RdpCertChallenge? get pendingRdpChallenge => _pendingRdpChallenge;

  /// Identity of an SSH host key entry: same endpoint + key type.
  bool _matches(KnownHost h, String host, int port, String keyType) =>
      h.protocol == KnownHost.protocolSsh && h.host == host && h.port == port && h.keyType == keyType;

  /// Completes when the last [load] finished (immediately before the first).
  Future<void> ready = Future<void>.value();

  Future<void> load() => ready = _load();

  Future<void> _load() async {
    if (_storage == null) return;
    _hosts = await _storage.loadKnownHosts();
    notifyListeners();
  }

  /// Removes [entry] regardless of protocol — SSH rows match on
  /// endpoint+keyType, RDP cert pins on endpoint alone (their keyType is
  /// empty and must not be forced through the SSH identity check).
  /// Bulk-inserts [incoming] entries, skipping duplicates on host:port:keyType.
  /// Returns the number of entries actually added.
  Future<int> importHosts(List<KnownHost> incoming) async {
    int added = 0;
    for (final entry in incoming) {
      final exists = _hosts.any((h) => _matches(h, entry.host, entry.port, entry.keyType));
      if (!exists) {
        _hosts.add(entry);
        added++;
      }
    }
    if (added > 0) {
      await _storage?.saveKnownHosts(_hosts);
      notifyListeners();
    }
    return added;
  }

  Future<void> remove(KnownHost entry) async {
    _hosts.removeWhere((h) => entry.protocol == KnownHost.protocolRdp
        ? h.protocol == KnownHost.protocolRdp &&
            h.host == entry.host &&
            h.port == entry.port
        : _matches(h, entry.host, entry.port, entry.keyType));
    await _storage?.saveKnownHosts(_hosts);
    notifyListeners();
  }

  Future<bool> verifyHostKey(
      String host, int port, String keyType, Uint8List fingerprint) async {
    final fp = KnownHost.bytesToFingerprint(fingerprint);
    final existing =
        _hosts.where((h) => _matches(h, host, port, keyType)).firstOrNull;

    // Pinned under another key type for this endpoint: a server (or MITM)
    // that merely offers a different host-key algorithm must not slip past the
    // pin. OpenSSH keeps one entry per type, so a legit new type is added on
    // explicit trust, never silently.
    final otherType = existing == null
        ? _hosts
            .where((h) =>
                h.protocol == KnownHost.protocolSsh &&
                h.host == host &&
                h.port == port)
            .firstOrNull
        : null;

    if (existing == null && otherType == null) {
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

    if (existing != null && existing.fingerprint == fp) return true;

    // Key mismatch — raise challenge; block until UI resolves it.
    // If a previous challenge is still pending (UI dialog stuck), reject it so
    // the prior caller doesn't hang forever and gets a clear "rejected" answer.
    _pendingChallenge?.reject();

    final challenge = HostKeyChallenge(
      host: host,
      port: port,
      keyType: keyType,
      oldFingerprint: (existing ?? otherType!).fingerprint,
      newFingerprint: fp,
      oldKeyType: existing == null ? otherType!.keyType : null,
    );
    _pendingChallenge = challenge;
    notifyListeners();

    final trusted = await challenge.result;
    // Only clear if it's still ours — a newer challenge may have replaced us.
    if (identical(_pendingChallenge, challenge)) _pendingChallenge = null;

    if (trusted) {
      _hosts.removeWhere((h) => _matches(h, host, port, keyType));
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

  // ── RDP certificate pinning ────────────────────────────────────────────────

  /// The pinned fingerprint for host:port, or null when never accepted.
  /// Fed to the Rust engine as `expected_fingerprint` so a mismatch aborts
  /// the connection before credentials are transmitted.
  String? pinnedRdpFingerprint(String host, int port) => _hosts
      .where((e) => e.protocol == KnownHost.protocolRdp && e.host == host && e.port == port)
      .firstOrNull
      ?.fingerprint;

  RdpCertVerdict verifyRdpCert({
    required String host,
    required int port,
    required String fingerprint,
  }) {
    final entry = _hosts
        .where((e) => e.protocol == KnownHost.protocolRdp && e.host == host && e.port == port)
        .firstOrNull;
    if (entry == null) return RdpCertVerdict.unknown;
    return entry.fingerprint == fingerprint
        ? RdpCertVerdict.trusted
        : RdpCertVerdict.mismatch;
  }

  Future<void> acceptRdpCert({
    required String host,
    required int port,
    required String fingerprint,
  }) async {
    _hosts.removeWhere(
        (e) => e.protocol == KnownHost.protocolRdp && e.host == host && e.port == port);
    _hosts.add(KnownHost(
      host: host,
      port: port,
      keyType: '',
      fingerprint: fingerprint,
      addedAt: DateTime.now(),
      protocol: KnownHost.protocolRdp,
    ));
    await _storage?.saveKnownHosts(_hosts);
    notifyListeners();
  }

  /// Creates a [RdpCertChallenge], stores it as [pendingRdpChallenge], and
  /// waits for the UI to resolve it. Call when [verifyRdpCert] returns
  /// [RdpCertVerdict.unknown] or [RdpCertVerdict.mismatch].
  Future<bool> challengeRdpCert({
    required String host,
    required int port,
    required String fingerprint,
    required bool isMismatch,
  }) async {
    _pendingRdpChallenge?.reject();

    final challenge = RdpCertChallenge(
      host: host,
      port: port,
      fingerprint: fingerprint,
      isMismatch: isMismatch,
    );
    _pendingRdpChallenge = challenge;
    notifyListeners();

    final trusted = await challenge.result;
    if (identical(_pendingRdpChallenge, challenge)) {
      _pendingRdpChallenge = null;
    }
    if (trusted) {
      await acceptRdpCert(host: host, port: port, fingerprint: fingerprint);
    } else {
      notifyListeners();
    }
    return trusted;
  }
}
