// The status bar inside the real terminal workspace: placement, the 900×600
// overflow check, and the perf guard (terminal output must not rebuild it).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/split_terminal_view.dart';
import 'package:yourssh/widgets/terminal_status_bar.dart';
import 'package:yourssh/widgets/workspace_side_panel.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/fake_recording.dart';
import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final long60 = 'x' * 60;

  late SessionProvider sessions;
  late TerminalLayoutProvider layout;
  late SettingsProvider settings;
  late ShellIntegrationProvider shell;
  late FakeRecording recording;
  late HostProvider hosts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'yourssh.hosts': jsonEncode([
        Host(
          id: 'b1',
          label: 'a' * 60,
          host: 'b1.example.com',
          username: 'j',
        ).toJson(),
        Host(
          id: 'b2',
          label: 'b' * 60,
          host: 'b2.example.com',
          username: 'j',
        ).toJson(),
      ]),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    final storage = StorageService();
    sessions = SessionProvider(SshService(storage), TabMetadataService());
    layout = TerminalLayoutProvider();
    settings = SettingsProvider();
    shell = ShellIntegrationProvider();
    recording = FakeRecording();
    hosts = HostProvider(storage);
    await hosts.ready;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    sessions.dispose();
    layout.dispose();
    settings.dispose();
    shell.dispose();
    recording.dispose();
    hosts.dispose();
  });

  SshSession connected(String label, {String? hostname}) {
    final s =
        SshSession(
            host: Host(
              label: label,
              host: hostname ?? 'prod.example.com',
              username: 'deploy',
              jumpHostIds: const ['b1', 'b2'],
              agentForwarding: true,
            ),
            status: SessionStatus.connected,
          )
          ..agentForwardingState = AgentForwardingState.active
          ..termType = 'xterm-256color';
    sessions.sessions.add(s);
    sessions.setActive(s.id);
    return s;
  }

  Widget harness() => MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ChangeNotifierProvider<TerminalLayoutProvider>.value(value: layout),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<ShellIntegrationProvider>.value(value: shell),
      ChangeNotifierProvider<RecordingProvider>.value(value: recording),
      ChangeNotifierProvider<HostProvider>.value(value: hosts),
      ChangeNotifierProvider<CommandHistoryProvider>(
        create: (_) => CommandHistoryProvider(),
      ),
      ChangeNotifierProvider<PluginProvider>(
        create: (_) => PluginProvider(plugins: [YourSSHSnippetsPlugin()]),
      ),
    ],
    child: ysTestApp(const SplitTerminalView()),
  );

  testWidgets('the workspace ends with the status bar of the active session', (
    tester,
  ) async {
    final s = connected('prod-web-01');
    await tester.pumpWidget(harness());
    await tester.pump();

    final bar = find.byType(SessionStatusBar);
    expect(bar, findsOneWidget);
    expect(tester.widget<SessionStatusBar>(bar).session, same(s));
    final view = tester.getRect(find.byType(SplitTerminalView));
    expect(tester.getRect(find.byType(YsStatusBar)).bottom, view.bottom);
  });

  testWidgets('900×600, split + side panel, 60-char label, host and hops: '
      'no overflow', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    connected('y' * 60);
    final s = connected(long60, hostname: '${'h' * 56}.com');
    recording
      ..elapsed = const Duration(hours: 12, minutes: 3, seconds: 4)
      ..setRecording(s.id, true);
    layout
      ..setLayout(SplitLayout.horizontal)
      ..toggleSidePanel(SidePanel.terminalConfig)
      ..toggleInputBar();

    await tester.pumpWidget(harness());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(WorkspaceSidePanel), findsOneWidget);
    expect(find.byType(SessionStatusBar), findsOneWidget);
    expect(tester.getSize(find.byType(YsStatusBar)).height, 22);
    expect(tester.takeException(), isNull);
  });

  testWidgets('100 output chunks do not rebuild the status bar', (
    tester,
  ) async {
    final s = connected('prod-web-01');
    recording
      ..elapsed = const Duration(seconds: 1)
      ..setRecording(s.id, true);
    await tester.pumpWidget(harness());
    await tester.pump();

    final barBuilds = SessionStatusBar.debugBuildCount;
    final sizeBuilds = TerminalSizeText.debugBuildCount;
    final recBuilds = RecElapsedText.debugBuildCount;
    expect(barBuilds, greaterThan(0));

    for (var i = 0; i < 100; i++) {
      s.terminal.write('line $i of output\r\n');
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      SessionStatusBar.debugBuildCount,
      barBuilds,
      reason: 'output must not rebuild the bar',
    );
    expect(
      TerminalSizeText.debugBuildCount,
      sizeBuilds,
      reason: 'cols×rows rebuilds only on resize',
    );
    // 100 × 16 ms = 1.6 s of output: the REC clock may tick at most twice.
    expect(RecElapsedText.debugBuildCount - recBuilds, lessThanOrEqualTo(2));
  });
}
