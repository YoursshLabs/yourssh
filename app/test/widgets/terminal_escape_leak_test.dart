// An Esc that dismisses a terminal overlay (search bar, context menus, theme
// picker) must be consumed by it and never reach the shell as a raw ESC byte;
// with no overlay open Esc must still reach the shell (vim, readline).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart' show TerminalView;
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/health_monitor_service.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/session_tab.dart';
import 'package:yourssh/widgets/terminal_view.dart';
import 'package:yourssh/widgets/theme_picker.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show YsDialogFrame;

import '../helpers/ys_test_app.dart';

void main() {
  late SessionProvider sessions;
  late SettingsProvider settings;
  late HostProvider hosts;
  late SshSession session;
  late List<String> sent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    sessions = SessionProvider(SshService(storage), TabMetadataService());
    hosts = HostProvider(storage);
    settings = SettingsProvider();
    session = SshSession(
      host: Host(label: 'prod', host: 'h.example.com', username: 'u'),
      status: SessionStatus.connected,
    );
    sessions.sessions.add(session);
    session.terminal.write('hello world\r\n');
    sent = [];
    session.terminal.onOutput = sent.add;
  });

  tearDown(() {
    sessions.dispose();
    settings.dispose();
  });

  Future<void> pumpAll(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider(create: (_) => ShellIntegrationProvider()),
          ChangeNotifierProvider(
            create: (_) => RecordingProvider(RecordingService(),
                getPath: () => '/tmp'),
          ),
          ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
          ChangeNotifierProvider(
            create: (_) => HealthMonitorService(
              measure: (_) async => null,
              connectedHostIds: () => const <String>[],
              pollSeconds: () => 0,
            ),
          ),
        ],
        child: ysTestApp(
          Column(children: [
            Row(children: [
              SessionTab(
                session: session,
                isActive: true,
                provider: sessions,
                onTap: () {},
              ),
              ThemePickerButton(currentTheme: 'Dracula', onChanged: (_) {}),
            ]),
            Expanded(child: SessionTerminalView(session: session)),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, Finder f) async {
    final g = await tester.startGesture(
      tester.getCenter(f),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<void> esc(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  testWidgets('Esc with no overlay reaches the shell', (tester) async {
    await pumpAll(tester);
    await esc(tester);
    expect(sent, contains('\x1b'));
  });

  testWidgets('Esc closing the terminal search bar is not sent', (tester) async {
    await pumpAll(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('terminal-search-field'));
    expect(field, findsOneWidget);
    await esc(tester);
    expect(field, findsNothing);
    expect(sent, isEmpty);
  });

  testWidgets('Esc closing the terminal context menu is not sent',
      (tester) async {
    await pumpAll(tester);
    await rightClick(tester, find.byType(TerminalView));
    expect(find.text('Select All'), findsOneWidget);
    await esc(tester);
    expect(find.text('Select All'), findsNothing);
    expect(sent, isEmpty);
  });

  testWidgets('Esc closing the tab context menu is not sent', (tester) async {
    await pumpAll(tester);
    await rightClick(tester, find.byType(SessionTab));
    expect(find.text('Color tag'), findsOneWidget);
    await esc(tester);
    expect(find.text('Color tag'), findsNothing);
    expect(sent, isEmpty);
  });

  testWidgets('Esc in the tab colour submenu: one press closes it, none sent',
      (tester) async {
    await pumpAll(tester);
    await rightClick(tester, find.byType(SessionTab));
    await tester.tap(find.text('Color tag'));
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);
    await esc(tester);
    // One Esc closes the submenu (the parent menu already closed when
    // "Color tag" was chosen), so a second Esc is a real Esc for the shell.
    expect(find.text('None'), findsNothing);
    expect(find.text('Color tag'), findsNothing);
    expect(sent, isEmpty);
    await esc(tester);
    expect(sent, ['\x1b']);
  });

  testWidgets('Esc closing the theme picker dialog is not sent',
      (tester) async {
    await pumpAll(tester);
    await tester.tap(find.byType(ThemePickerButton));
    await tester.pumpAndSettle();
    expect(find.byType(YsDialogFrame), findsOneWidget);
    await esc(tester);
    expect(find.byType(YsDialogFrame), findsNothing);
    expect(sent, isEmpty);
  });
}
