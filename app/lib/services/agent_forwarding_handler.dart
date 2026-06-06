import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_key.dart';
import 'system_agent_proxy.dart';

/// Serves forwarded `auth-agent@openssh.com` channels (issue #49).
///
/// Primary path: relay each agent request verbatim over a fresh
/// [SystemAgentProxy] connection (the agent protocol is strictly serial per
/// connection, so connection-per-request sidesteps interleaving between
/// concurrent forwarded channels and stale sockets after agent restarts —
/// the same model `ssh-add` uses).
///
/// Fallback: when no system agent is reachable, app-Keychain keys are served
/// through dartssh2's [SSHKeyPairAgent], built lazily on first use and cached
/// for the lifetime of this handler (one SSH connection). The fallback only
/// triggers on connect failure — a request that fails *after* connecting
/// propagates instead, so we never switch key sources mid-request. Across
/// requests the source CAN switch (system agent dies between an identity
/// listing and the follow-up sign): the sign then fails once if the listed
/// key isn't in the Keychain, which matches the per-request retry design.
class AgentForwardingHandler implements SSHAgentHandler {
  AgentForwardingHandler({
    this._connectSystemAgent = SystemAgentProxy.connect,
    required this._loadKeychainIdentities,
    this.onRequestServed,
  });

  final Future<SystemAgentProxy> Function() _connectSystemAgent;
  final Future<List<SSHKeyPair>> Function() _loadKeychainIdentities;

  /// Fired after each successfully served request — `usedFallback` is true
  /// when the reply came from app-Keychain keys instead of the system agent.
  /// Exceptions are swallowed: observability must never fail the round trip.
  final void Function(bool usedFallback)? onRequestServed;

  // Memoizes the FUTURE (created synchronously, no await between the null
  // check and the assignment) so concurrent first-use requests share one
  // Keychain load instead of racing `??=` across an await.
  Future<SSHKeyPairAgent>? _fallback;

  void _notifyServed(bool usedFallback) {
    try {
      onRequestServed?.call(usedFallback);
    } catch (_) {}
  }

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    final SystemAgentProxy proxy;
    try {
      proxy = await _connectSystemAgent();
    } on SSHAgentUnavailableException {
      final fallback = await (_fallback ??=
          _loadKeychainIdentities().then(SSHKeyPairAgent.new));
      final response = await fallback.handleRequest(request);
      _notifyServed(true);
      return response;
    }
    try {
      final response = await proxy.roundtrip(request);
      _notifyServed(false);
      return response;
    } on SSHAgentUnavailableException {
      rethrow;
    } catch (e) {
      throw SSHAgentUnavailableException(
          'Agent I/O error after connect: $e');
    } finally {
      // Swallow close errors — a broken-pipe socket throws on close() too,
      // and a finally-block throw would replace the already-wrapped exception.
      await proxy.close().catchError((_) {});
    }
  }
}

/// Reads the PEM private key at [path] and parses it with an optional
/// passphrase (null/empty → unencrypted). Shared by interactive auth
/// (`SshService._resolveIdentities`) and the agent-forwarding fallback so the
/// passphrase normalization rule lives in one place.
Future<List<SSHKeyPair>> loadKeyPairsFromFile(
  String path,
  String? passphrase,
) async {
  final pem = await File(path).readAsString();
  return SSHKeyPair.fromPem(
    pem,
    passphrase?.isNotEmpty == true ? passphrase : null,
  );
}

/// Loads every Keychain key that opens without user interaction —
/// unencrypted, or encrypted with a stored passphrase. Entries that fail
/// (missing file, wrong/missing passphrase, parse error) are skipped so one
/// broken entry never blocks the rest of the Keychain. Certificates are not
/// served in v1 (private keys only).
Future<List<SSHKeyPair>> loadKeychainKeyPairs(
  Iterable<SshKeyEntry> entries,
  Future<String?> Function(String keyId) loadPassphrase,
) async {
  final pairs = <SSHKeyPair>[];
  for (final entry in entries) {
    try {
      final passphrase = await loadPassphrase(entry.id);
      pairs.addAll(
          await loadKeyPairsFromFile(entry.privateKeyPath, passphrase));
    } catch (_) {
      // Skipped by design — forwarding serves whatever is loadable.
    }
  }
  return pairs;
}
