import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

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
/// propagates instead, so we never switch key sources mid-request.
class AgentForwardingHandler implements SSHAgentHandler {
  AgentForwardingHandler({
    Future<SystemAgentProxy> Function() connectSystemAgent =
        SystemAgentProxy.connect,
    required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
  })  : _connectSystemAgent = connectSystemAgent,
        _loadKeychainIdentities = loadKeychainIdentities;

  final Future<SystemAgentProxy> Function() _connectSystemAgent;
  final Future<List<SSHKeyPair>> Function() _loadKeychainIdentities;

  SSHKeyPairAgent? _fallback;

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    final SystemAgentProxy proxy;
    try {
      proxy = await _connectSystemAgent();
    } on SSHAgentUnavailableException {
      final fallback =
          _fallback ??= SSHKeyPairAgent(await _loadKeychainIdentities());
      return fallback.handleRequest(request);
    }
    try {
      return await proxy.roundtrip(request);
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
