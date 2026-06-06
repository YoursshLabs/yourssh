import 'package:dartssh2/dartssh2.dart';

import 'system_agent_proxy.dart';

/// Outcome of a local agent probe — what a forwarded channel would serve
/// right now. Mirrors AgentForwardingHandler's source order: system agent
/// first, app-Keychain keys only when the agent is unreachable.
sealed class AgentProbeResult {
  const AgentProbeResult();
}

/// System agent reachable; it holds [identityCount] identities.
class AgentProbeSystem extends AgentProbeResult {
  const AgentProbeSystem(this.identityCount);
  final int identityCount;
}

/// No system agent; forwarding would serve [keyCount] app-Keychain keys.
class AgentProbeKeychain extends AgentProbeResult {
  const AgentProbeKeychain(this.keyCount);
  final int keyCount;
}

/// Nothing to serve — no agent and no loadable Keychain keys, or the agent
/// failed mid-probe ([detail] carries the error in that case).
class AgentProbeNothing extends AgentProbeResult {
  const AgentProbeNothing([this.detail]);
  final String? detail;
}

/// Connects to the system agent, lists identities, closes. The default
/// identity source for [probeAgentStatus]; split out so tests inject failures.
Future<List<SSHKeyPair>> listSystemAgentIdentities() async {
  final proxy = await SystemAgentProxy.connect();
  try {
    return await proxy.getIdentities();
  } finally {
    // Swallow close errors — same rationale as AgentForwardingHandler.
    await proxy.close().catchError((_) {});
  }
}

/// Pre-connect probe behind the host panel's agent status line. Never
/// throws — every failure maps to a displayable result.
Future<AgentProbeResult> probeAgentStatus({
  Future<List<SSHKeyPair>> Function() listAgentIdentities =
      listSystemAgentIdentities,
  required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
}) async {
  try {
    final identities = await listAgentIdentities();
    return AgentProbeSystem(identities.length);
  } on SSHAgentUnavailableException {
    // Same trigger AgentForwardingHandler uses for its Keychain fallback.
    try {
      final keys = await loadKeychainIdentities();
      return keys.isEmpty
          ? const AgentProbeNothing()
          : AgentProbeKeychain(keys.length);
    } catch (_) {
      return const AgentProbeNothing();
    }
  } catch (e) {
    // Agent reachable but broken (malformed reply, I/O error mid-listing) —
    // runtime forwarding would not fall back here, so neither does the probe.
    return AgentProbeNothing('$e');
  }
}
