import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/split_terminal_view.dart';
import 'package:yourssh/widgets/terminal_header_chips.dart';
import 'package:yourssh/widgets/workspace_side_panel.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../helpers/ys_test_app.dart';

void main() {
  late SessionProvider sessions;
  late TerminalLayoutProvider layout;
  late SettingsProvider settings;
  late ShellIntegrationProvider shell;
  late RecordingProvider recording;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sessions =
        SessionProvider(SshService(StorageService()), TabMetadataService());
    layout = TerminalLayoutProvider();
    settings = SettingsProvider();
    shell = ShellIntegrationProvider();
    recording = RecordingProvider(RecordingService(),
        getPath: () => Directory.systemTemp.path);
  });

  tearDown(() {
    sessions.dispose();
    layout.dispose();
    settings.dispose();
    shell.dispose();
    recording.dispose();
  });

  SshSession ssh(String label) => SshSession(
        host: Host(label: label, host: 'h.example.com', username: 'deploy'),
      );

  LocalSession local() =>
      LocalSession(terminal: Terminal(), status: LocalSessionStatus.running);

  void add(AppSession s) {
    sessions.sessions.add(s);
    sessions.setActive(s.id);
  }

  Widget harness() => MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
          ChangeNotifierProvider<TerminalLayoutProvider>.value(value: layout),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ShellIntegrationProvider>.value(value: shell),
          ChangeNotifierProvider<RecordingProvider>.value(value: recording),
          ChangeNotifierProvider<PluginProvider>(
              create: (_) => PluginProvider(plugins: [YourSSHSnippetsPlugin()])),
        ],
        child: ysTestApp(const SplitTerminalView()),
      );

  testWidgets('smoke: renders header chips and the toolbar for a session',
      (tester) async {
    add(ssh('prod-web-01'));
    await tester.pumpWidget(harness());
    expect(find.byType(TerminalHeaderChips), findsOneWidget);
    expect(find.text('deploy@h.example.com'), findsOneWidget);
    expect(find.byTooltip('Toggle Terminal Settings'), findsOneWidget);
  });

  testWidgets('smoke: shows the empty state without sessions', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('No active sessions'), findsOneWidget);
  });

  testWidgets('split layouts draw a token-styled divider', (tester) async {
    add(ssh('a'));
    add(ssh('b'));
    layout.setLayout(SplitLayout.horizontal);
    await tester.pumpWidget(harness());
    expect(find.byKey(const Key('split-divider')), findsOneWidget);
    layout.setLayout(SplitLayout.quad);
    await tester.pump();
    expect(find.byKey(const Key('split-divider')), findsNWidgets(3));
  });

  testWidgets('900x600 with side panel open and a 60 char label: no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    add(ssh('x' * 60));
    layout.toggleSidePanel(SidePanel.terminalConfig);
    layout.setLayout(SplitLayout.horizontal);
    await tester.pumpWidget(harness());
    // The connecting animation never settles; pump a few frames instead.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(WorkspaceSidePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('writing output does not rebuild the side panel or header chips',
      (tester) async {
    final s = local();
    add(s);
    layout.toggleSidePanel(SidePanel.terminalConfig);
    await tester.pumpWidget(harness());
    await tester.pump();
    final panelBuilds = WorkspaceSidePanel.debugBuildCount;
    final chipBuilds = TerminalHeaderChips.debugBuildCount;
    expect(panelBuilds, greaterThan(0));
    expect(chipBuilds, greaterThan(0));

    for (var i = 0; i < 100; i++) {
      s.terminal.write('line $i of output\r\n');
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(WorkspaceSidePanel.debugBuildCount, panelBuilds);
    expect(TerminalHeaderChips.debugBuildCount, chipBuilds);
  });
}
