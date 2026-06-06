import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/agent_forwarding_handler.dart'
    show loadKeyPairsFromFile;
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

void main() {
  late List<SSHKeyPair> onePair;

  setUpAll(() async {
    // Same fixture the agent-forwarding handler tests use.
    onePair = await loadKeyPairsFromFile('test/fixtures/keys/id_ed25519', null);
  });

  test('system agent reachable maps to AgentProbeSystem with identity count',
      () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async => [...onePair, ...onePair],
      loadKeychainIdentities: () async => onePair,
    );
    expect(result, isA<AgentProbeSystem>());
    expect((result as AgentProbeSystem).identityCount, 2);
  });

  test('agent unavailable maps to Keychain fallback with key count', () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async =>
          throw const SSHAgentUnavailableException('none'),
      loadKeychainIdentities: () async => onePair,
    );
    expect(result, isA<AgentProbeKeychain>());
    expect((result as AgentProbeKeychain).keyCount, 1);
  });

  test('agent unavailable and zero Keychain keys maps to AgentProbeNothing',
      () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async =>
          throw const SSHAgentUnavailableException('none'),
      loadKeychainIdentities: () async => const <SSHKeyPair>[],
    );
    expect(result, isA<AgentProbeNothing>());
    expect((result as AgentProbeNothing).detail, isNull);
  });

  test('a throwing Keychain loader maps to AgentProbeNothing, never throws',
      () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async =>
          throw const SSHAgentUnavailableException('none'),
      loadKeychainIdentities: () async => throw Exception('keychain broken'),
    );
    expect(result, isA<AgentProbeNothing>());
  });

  test('agent failure after connect maps to AgentProbeNothing with detail '
      'and does not consult the Keychain', () async {
    var keychainCalls = 0;
    final result = await probeAgentStatus(
      listAgentIdentities: () async => throw Exception('malformed reply'),
      loadKeychainIdentities: () async {
        keychainCalls++;
        return onePair;
      },
    );
    expect(result, isA<AgentProbeNothing>());
    expect((result as AgentProbeNothing).detail, contains('malformed reply'));
    expect(keychainCalls, 0);
  });
}
