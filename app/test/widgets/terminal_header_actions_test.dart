// The terminal workspace header with every trailing control present:
// network stats, Share and the AI chat toggle (MainScreen's toolbarTrailing).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/network_stats.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/share_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/network_stats_overlay.dart';
import 'package:yourssh/widgets/share_session_dialog.dart';
import 'package:yourssh/widgets/split_terminal_view.dart';
import 'package:yourssh/widgets/terminal_header_actions.dart';
import 'package:yourssh/widgets/workspace_side_panel.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/fake_recording.dart';
import '../helpers/ys_test_app.dart';

class _Share extends ShareProvider {
  _Share(SyncProvider sync) : super(syncProvider: sync);
  @override
  bool get canShare => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  late StorageService storage;
  late SessionProvider sessions;
  late TerminalLayoutProvider layout;
  late SettingsProvider settings;
  late ShellIntegrationProvider shell;
  late FakeRecording recording;
  late HostProvider hosts;
  late SyncProvider sync;
  late ShareProvider share;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'networkStatsEnabled': true,
      'yourssh.hosts': jsonEncode([
        Host(
          id: 'b1',
          label: 'b' * 60,
          host: 'b1.example.com',
          username: 'j',
        ).toJson(),
      ]),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    storage = StorageService();
    sessions = SessionProvider(SshService(storage), TabMetadataService());
    layout = TerminalLayoutProvider();
    settings = SettingsProvider();
    shell = ShellIntegrationProvider();
    recording = FakeRecording();
    hosts = HostProvider(storage);
    await hosts.ready;
    sync = SyncProvider();
    share = _Share(sync);
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
    share.dispose();
    sync.dispose();
  });

  SshSession connected(String label) {
    final s = SshSession(
      host: Host(
        label: label,
        host: '${'h' * 56}.com',
        username: 'deploy',
        jumpHostIds: const ['b1'],
        agentForwarding: true,
      ),
      status: SessionStatus.connected,
    )..termType = 'xterm-256color';
    sessions.sessions.add(s);
    sessions.setActive(s.id);
    return s;
  }

  Widget harness(SshSession active, {required VoidCallback onToggleAi}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
          ChangeNotifierProvider<TerminalLayoutProvider>.value(value: layout),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ShellIntegrationProvider>.value(value: shell),
          ChangeNotifierProvider<RecordingProvider>.value(value: recording),
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          ChangeNotifierProvider<ShareProvider>.value(value: share),
          ChangeNotifierProvider<CommandHistoryProvider>(
            create: (_) => CommandHistoryProvider(),
          ),
          ChangeNotifierProvider<PluginProvider>(
            create: (_) => PluginProvider(plugins: [YourSSHSnippetsPlugin()]),
          ),
          Provider<SshService>.value(value: SshService(storage)),
        ],
        child: ysTestApp(
          SplitTerminalView(
            toolbarTrailing: TerminalHeaderActions(
              active: active,
              aiConfigured: true,
              aiOpen: false,
              onToggleAi: onToggleAi,
            ),
          ),
        ),
      );

  testWidgets(
    '900×600, 60-char label, split + side panel, network stats + Share + AI '
    'all shown: no overflow, nothing covers the header buttons',
    (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      connected('y' * 60);
      final s = connected('x' * 60);
      layout
        ..setLayout(SplitLayout.horizontal)
        ..toggleSidePanel(SidePanel.terminalConfig);
      var aiToggles = 0;

      await tester.pumpWidget(harness(s, onToggleAi: () => aiToggles++));
      await tester.pump(); // settings load
      final dynamic stats = tester.state(find.byType(NetworkStatsOverlay));
      stats.debugSetDelta(
        const NetworkStatsDelta(rxBytesPerSec: 1024, txBytesPerSec: 2048),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(WorkspaceSidePanel), findsOneWidget);
      expect(find.byIcon(FLucideIcons.arrowDown), findsOneWidget);
      expect(find.byTooltip('Share this terminal'), findsOneWidget);
      expect(find.byTooltip('Open AI Chat'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The trailing controls follow the header actions, they do not cover
      // them.
      final settingsBtn = tester.getRect(
        find.byTooltip('Toggle Terminal Settings'),
      );
      for (final f in [
        find.byIcon(FLucideIcons.arrowDown),
        find.byKey(const Key('share-terminal-button')),
        find.byKey(const Key('ai-chat-toggle')),
      ]) {
        expect(tester.getRect(f).overlaps(settingsBtn), isFalse);
        expect(tester.getRect(f).left, greaterThanOrEqualTo(settingsBtn.right));
      }

      await tester.tap(find.byKey(const Key('ai-chat-toggle')));
      await tester.pumpAndSettle();
      expect(aiToggles, 1);

      await tester.tap(find.byKey(const Key('share-terminal-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ShareSessionDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Share hides for a session that is not connected', (
    tester,
  ) async {
    final s = connected('prod');
    s.status = SessionStatus.connecting;
    await tester.pumpWidget(harness(s, onToggleAi: () {}));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('share-terminal-button')), findsNothing);
    expect(find.byKey(const Key('ai-chat-toggle')), findsOneWidget);
  });
}
