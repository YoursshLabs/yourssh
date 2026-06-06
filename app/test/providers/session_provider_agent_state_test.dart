import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

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

  group('handleAgentForwardingEvent', () {
    late SessionProvider provider;

    setUp(() {
      provider =
          SessionProvider(SshService(StorageService()), TabMetadataService());
    });

    tearDown(() => provider.dispose());

    SshSession seed(Host host) {
      final s = SshSession(host: host, status: SessionStatus.connected);
      provider.sessions.add(s);
      return s;
    }

    test('host-scoped served event moves every session on that host to active',
        () {
      final s1 = seed(_host('h1'));
      final s2 = seed(_host('h1'));
      final other = seed(_host('h2'));

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);

      expect(s1.agentForwardingState, AgentForwardingState.active);
      expect(s2.agentForwardingState, AgentForwardingState.active);
      expect(other.agentForwardingState, AgentForwardingState.ready);
    });

    test('session-scoped refused only touches that session', () {
      final s1 = seed(_host('h1'));
      final s2 = seed(_host('h1'));

      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.refused);

      expect(s1.agentForwardingState, AgentForwardingState.refused);
      expect(s2.agentForwardingState, AgentForwardingState.ready);
    });

    test('host-scoped event never overrides a per-shell refusal', () {
      final s1 = seed(_host('h1'));
      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.refused);

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);

      expect(s1.agentForwardingState, AgentForwardingState.refused);
    });

    test('session-scoped ready resets refused (reconnect)', () {
      final s1 = seed(_host('h1'));
      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.refused);

      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.ready);

      expect(s1.agentForwardingState, AgentForwardingState.ready);
    });

    test('event for an unknown session id is a no-op', () {
      seed(_host('h1'));
      expect(
        () => provider.handleAgentForwardingEvent(
            'h1', 'gone', AgentForwardingState.active),
        returnsNormally,
      );
    });

    test('notifies listeners once per effective change, not on no-ops', () {
      final s1 = seed(_host('h1'));
      var notifies = 0;
      provider.addListener(() => notifies++);

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);
      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active); // same state — no change

      expect(notifies, 1);
      expect(s1.agentForwardingState, AgentForwardingState.active);
    });

    test('a host-scoped event changing two sessions notifies exactly once',
        () {
      final s1 = seed(_host('h1'));
      final s2 = seed(_host('h1'));
      var notifies = 0;
      provider.addListener(() => notifies++);

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);

      expect(notifies, 1);
      expect(s1.agentForwardingState, AgentForwardingState.active);
      expect(s2.agentForwardingState, AgentForwardingState.active);
    });

    test('watch sessions are never touched, even on host-id collision', () {
      final watch = SshSession.watch(watchedTitle: 'shared');
      // Force the synthetic host id to collide with a real one.
      final real = seed(_host(watch.host.id));
      provider.sessions.add(watch);

      provider.handleAgentForwardingEvent(
          watch.host.id, null, AgentForwardingState.active);

      expect(real.agentForwardingState, AgentForwardingState.active);
      expect(watch.agentForwardingState, AgentForwardingState.off);
    });
  });
}
