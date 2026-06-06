import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

Host _host(String id, {bool forwarding = true}) => Host(
      id: id,
      label: id,
      host: '$id.example.com',
      port: 22,
      username: 'u',
      agentForwarding: forwarding,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('constructor derives ready when the host has forwarding on, off '
      'otherwise', () {
    expect(SshSession(host: _host('a')).agentForwardingState,
        AgentForwardingState.ready);
    expect(SshSession(host: _host('b', forwarding: false)).agentForwardingState,
        AgentForwardingState.off);
  });
}
