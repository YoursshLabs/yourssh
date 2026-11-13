import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/models/shell_profile.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/models/vnc_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/terminal_status_bar.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient, RdpConfig;
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as rdp;
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:yourssh_vnc/yourssh_vnc.dart' show VncClient, VncConfig;
// ignore: implementation_imports
import 'package:yourssh_vnc/src/generated/api.dart' as vnc;

import '../helpers/fake_recording.dart';
import '../helpers/ys_test_app.dart';

/// Every status-bar field key shown under [SessionStatusBar].
Set<String> fieldKeys(WidgetTester tester) => tester
    .widgetList(
      find.descendant(
        of: find.byType(SessionStatusBar),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('status-'),
        ),
      ),
    )
    .map((w) => (w.key! as ValueKey<String>).value)
    .toSet();

String fieldText(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data ?? '')
      .where((t) => t.isNotEmpty);
  return texts.join(' ');
}

Host bastion(String id, String label) =>
    Host(id: id, label: label, host: '$id.example.com', username: 'jump');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late SessionProvider sessions;
  late SettingsProvider settings;
  late FakeRecording recording;
  late HostProvider hosts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'yourssh.hosts': jsonEncode([
        bastion('b1', 'bastion-eu').toJson(),
        bastion('b2', 'k8s-bastion').toJson(),
      ]),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    final storage = StorageService();
    sessions = SessionProvider(SshService(storage), TabMetadataService());
    settings = SettingsProvider();
    recording = FakeRecording();
    hosts = HostProvider(storage);
    await hosts.ready;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    sessions.dispose();
    settings.dispose();
    recording.dispose();
    hosts.dispose();
  });

  Widget harness(AppSession session) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<RecordingProvider>.value(value: recording),
      ChangeNotifierProvider<HostProvider>.value(value: hosts),
    ],
    child: ysTestApp(
      Align(
        alignment: Alignment.bottomCenter,
        child: SessionStatusBar(session: session),
      ),
    ),
  );

  SshSession sshSession({
    SessionStatus status = SessionStatus.connected,
    List<String> jumps = const [],
    bool agentForwarding = false,
    String? termType,
  }) {
    final s = SshSession(
      host: Host(
        id: 'h1',
        label: 'prod-web-01',
        host: 'prod.example.com',
        username: 'deploy',
        jumpHostIds: jumps,
        agentForwarding: agentForwarding,
        termType: termType,
      ),
      status: status,
    );
    sessions.sessions.add(s);
    return s;
  }

  group('SSH', () {
    testWidgets('full session shows exactly the spec fields', (tester) async {
      final s = sshSession(
        jumps: ['b1', 'b2'],
        agentForwarding: true,
        termType: 'screen-256color',
      );
      s
        ..agentForwardingState = AgentForwardingState.active
        ..termType = 'screen-256color';
      recording
        ..elapsed = const Duration(minutes: 4, seconds: 12)
        ..setRecording(s.id, true);

      await tester.pumpWidget(harness(s));

      expect(fieldKeys(tester), {
        'status-connection',
        'status-user-host',
        'status-via',
        'status-agent',
        'status-term',
        'status-size',
        'status-rec',
      });
      expect(fieldText(tester, 'status-connection'), 'Connected');
      expect(fieldText(tester, 'status-user-host'), 'deploy@prod.example.com');
      expect(fieldText(tester, 'status-via'), 'via bastion-eu → k8s-bastion');
      expect(fieldText(tester, 'status-agent'), 'Agent forwarding active');
      expect(fieldText(tester, 'status-term'), 'screen-256color');
      expect(fieldText(tester, 'status-size'), '80×24');
      expect(fieldText(tester, 'status-rec'), 'REC 00:04:12');
    });

    testWidgets('direct session without recording: no via, no REC',
        (tester) async {
      final s = sshSession()..termType = 'xterm-256color';
      await tester.pumpWidget(harness(s));

      expect(fieldKeys(tester), {
        'status-connection',
        'status-user-host',
        'status-agent',
        'status-term',
        'status-size',
      });
      expect(fieldText(tester, 'status-agent'), 'Agent forwarding off');
      expect(fieldText(tester, 'status-term'), 'xterm-256color');
    });

    testWidgets('TERM is the value the session connected with: a later '
        'Settings change does not alter it', (tester) async {
      final s = sshSession()..termType = 'xterm-256color';
      await tester.pumpWidget(harness(s));
      expect(fieldText(tester, 'status-term'), 'xterm-256color');

      await settings.save(terminalType: 'vt100');
      await tester.pump();
      expect(settings.terminalType, 'vt100');
      expect(fieldText(tester, 'status-term'), 'xterm-256color');
    });

    testWidgets('no TERM before the provider resolved one', (tester) async {
      final s = sshSession(status: SessionStatus.connecting);
      await tester.pumpWidget(harness(s));
      expect(fieldKeys(tester), isNot(contains('status-term')));
    });

    testWidgets('connecting / error: status text, no cols×rows', (
      tester,
    ) async {
      final s = sshSession(status: SessionStatus.connecting);
      await tester.pumpWidget(harness(s));
      expect(fieldText(tester, 'status-connection'), 'Connecting…');
      expect(fieldKeys(tester), isNot(contains('status-size')));

      s
        ..status = SessionStatus.error
        ..errorMessage = 'Auth failed: permission denied';
      sessions.renameSession(s.id, null); // any provider notification
      await tester.pump();
      expect(fieldText(tester, 'status-connection'), 'Error');
      expect(find.byTooltip('Auth failed: permission denied'), findsOneWidget);
    });

    testWidgets('user@host follows an edit of the stored host; terminal '
        'output does not rebuild the bar', (tester) async {
      final s = sshSession()..termType = 'xterm-256color';
      await tester.runAsync(() => hosts.addHost(s.host));
      await tester.pumpWidget(harness(s));
      expect(fieldText(tester, 'status-user-host'), 'deploy@prod.example.com');

      await tester.runAsync(
        () => hosts.updateHost(
          s.host.copyWith(username: 'ops', host: 'new.example.com'),
        ),
      );
      await tester.pump();
      expect(fieldText(tester, 'status-user-host'), 'ops@new.example.com');

      final builds = SessionStatusBar.debugBuildCount;
      for (var i = 0; i < 20; i++) {
        s.terminal.write('output $i\r\n');
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(SessionStatusBar.debugBuildCount, builds);
    });

    testWidgets('a deleted host falls back to the session snapshot',
        (tester) async {
      final s = sshSession()..termType = 'xterm-256color';
      await tester.runAsync(() => hosts.addHost(s.host));
      await tester.pumpWidget(harness(s));
      await tester.runAsync(() => hosts.deleteHost(s.host.id));
      await tester.pump();
      expect(fieldText(tester, 'status-user-host'), 'deploy@prod.example.com');
    });

    testWidgets('agent-forwarding events update the field', (tester) async {
      final s = sshSession(agentForwarding: true);
      await tester.pumpWidget(harness(s));
      expect(fieldText(tester, 'status-agent'), 'Agent forwarding ready');

      sessions.handleAgentForwardingEvent(
        'h1',
        s.id,
        AgentForwardingState.refused,
      );
      await tester.pump();
      expect(fieldText(tester, 'status-agent'), 'Agent forwarding refused');
    });

    testWidgets('cols×rows follows a terminal resize', (tester) async {
      final s = sshSession();
      await tester.pumpWidget(harness(s));
      expect(fieldText(tester, 'status-size'), '80×24');

      s.terminal.resize(132, 43);
      await tester.pump(); // the post-frame size check
      await tester.pump(); // the size label's own rebuild
      expect(fieldText(tester, 'status-size'), '132×43');
    });

    testWidgets('REC elapsed ticks once a second without rebuilding the bar', (
      tester,
    ) async {
      final s = sshSession();
      recording
        ..elapsed = const Duration(seconds: 5)
        ..setRecording(s.id, true);
      await tester.pumpWidget(harness(s));
      expect(fieldText(tester, 'status-rec'), 'REC 00:00:05');
      final barBuilds = SessionStatusBar.debugBuildCount;
      final tickBuilds = RecElapsedText.debugBuildCount;

      recording.elapsed = const Duration(seconds: 6);
      await tester.pump(const Duration(seconds: 1));
      expect(fieldText(tester, 'status-rec'), 'REC 00:00:06');
      expect(SessionStatusBar.debugBuildCount, barBuilds);
      expect(RecElapsedText.debugBuildCount, tickBuilds + 1);

      recording.setRecording(s.id, false);
      await tester.pump();
      expect(fieldKeys(tester), isNot(contains('status-rec')));
    });
  });

  group('Local PTY', () {
    testWidgets('shows exactly the shell and cols×rows', (tester) async {
      final s = LocalSession(
        terminal: Terminal(),
        profile: const ShellProfile(
          id: 'fish',
          name: 'fish',
          executable: '/usr/bin/fish',
        ),
      );
      await tester.pumpWidget(harness(s));
      expect(fieldKeys(tester), {'status-shell', 'status-size'});
      expect(fieldText(tester, 'status-shell'), 'fish');
      expect(fieldText(tester, 'status-size'), '80×24');
    });

    testWidgets('platform default shell is named by its executable', (
      tester,
    ) async {
      final s = LocalSession(terminal: Terminal());
      await tester.pumpWidget(harness(s));
      expect(
        fieldText(tester, 'status-shell'),
        LocalShellService.platformDefaultShellName(),
      );
    });
  });

  group('RDP/VNC', () {
    testWidgets('RDP shows exactly resolution and status', (tester) async {
      final events = StreamController<rdp.RdpEvent>();
      final s = RdpSession(
        host: Host(
          id: 'r1',
          label: 'win',
          host: '10.0.0.2',
          port: 3389,
          username: 'u',
          protocol: HostProtocol.rdp,
        ),
        client: RdpClient(
          RdpConfig(
            targetHost: '10.0.0.2',
            targetPort: 3389,
            username: 'u',
            password: '',
            domain: null,
            width: 1280,
            height: 800,
            security: 'auto',
          ),
        ),
        width: 1280,
        height: 800,
      )..attach(events.stream);
      addTearDown(events.close);

      await tester.pumpWidget(harness(s));
      expect(fieldKeys(tester), {'status-connection', 'status-resolution'});
      expect(fieldText(tester, 'status-connection'), 'Connecting…');
      // Not negotiated yet: the requested size is marked as such.
      expect(fieldText(tester, 'status-resolution'), '1280×800 (requested)');

      events.add(
        rdp.RdpEvent.connected(
          cert: const rdp.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
          desktopWidth: 1920,
          desktopHeight: 1080,
        ),
      );
      await tester.pump();
      expect(fieldText(tester, 'status-connection'), 'Connected');
      expect(fieldText(tester, 'status-resolution'), '1920×1080');

      // A frame-only repaint must not rebuild the bar.
      final builds = SessionStatusBar.debugBuildCount;
      // ignore: invalid_use_of_protected_member
      s.notifyListeners();
      await tester.pump();
      expect(SessionStatusBar.debugBuildCount, builds);

      // No live desktop, no resolution.
      events.add(const rdp.RdpEvent.disconnected(reason: 'bye'));
      await tester.pump(); // deliver the event
      await tester.pump(); // rebuild
      expect(fieldText(tester, 'status-connection'), 'Disconnected');
      expect(fieldKeys(tester), {'status-connection'});
    });

    testWidgets('VNC shows status, and resolution once known', (tester) async {
      final events = StreamController<vnc.VncEvent>();
      final s = VncSession(
        host: Host(
          id: 'v1',
          label: 'desktop',
          host: '10.0.0.5',
          port: 5900,
          username: 'u',
          protocol: HostProtocol.vnc,
        ),
        client: VncClient(
          VncConfig(
            targetHost: '10.0.0.5',
            targetPort: 5900,
            username: 'u',
            password: '',
          ),
        ),
      )..attach(events.stream);
      addTearDown(events.close);

      await tester.pumpWidget(harness(s));
      expect(fieldKeys(tester), {'status-connection'});

      events.add(const vnc.VncEvent.connected(width: 800, height: 600));
      await tester.pump();
      expect(fieldKeys(tester), {'status-connection', 'status-resolution'});
      expect(fieldText(tester, 'status-connection'), 'Connected');
      expect(fieldText(tester, 'status-resolution'), '800×600');
    });
  });

  test('formatRecElapsed pads hours, minutes and seconds', () {
    expect(formatRecElapsed(Duration.zero), '00:00:00');
    expect(
      formatRecElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '01:02:03',
    );
    expect(formatRecElapsed(const Duration(hours: 123)), '123:00:00');
  });

  testWidgets('status bar sits on the chrome token strip', (tester) async {
    final s = sshSession();
    await tester.pumpWidget(harness(s));
    expect(find.byType(YsStatusBar), findsOneWidget);
  });
}
