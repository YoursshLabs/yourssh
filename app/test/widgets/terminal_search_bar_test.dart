// The in-terminal search bar (Cmd/Ctrl+F) of SessionTerminalView.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:xterm/xterm.dart' show TerminalView;
import 'package:yourssh/widgets/terminal_view.dart';

import '../helpers/fake_recording.dart';
import '../helpers/ys_test_app.dart';

void main() {
  late SessionProvider sessions;
  late SettingsProvider settings;
  late ShellIntegrationProvider shell;
  late FakeRecording recording;
  late SshSession session;

  final searchField = find.byKey(const Key('terminal-search-field'));
  final countLabel = find.byKey(const Key('terminal-search-count'));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sessions = SessionProvider(
      SshService(StorageService()),
      TabMetadataService(),
    );
    settings = SettingsProvider();
    shell = ShellIntegrationProvider();
    recording = FakeRecording();
    session = SshSession(
      host: Host(label: 'prod', host: 'h.example.com', username: 'u'),
      status: SessionStatus.connected,
    );
    session.terminal.write('hello world\r\nsay hello\r\nnothing here\r\n');
  });

  tearDown(() {
    sessions.dispose();
    settings.dispose();
    shell.dispose();
    recording.dispose();
  });

  Future<void> pumpView(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ShellIntegrationProvider>.value(value: shell),
          ChangeNotifierProvider<RecordingProvider>.value(value: recording),
          ChangeNotifierProvider<CommandHistoryProvider>(
            create: (_) => CommandHistoryProvider(),
          ),
        ],
        child: ysTestApp(SessionTerminalView(session: session)),
      ),
    );
    await tester.pump();
  }

  Future<void> openSearch(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  String count(WidgetTester tester) => tester.widget<Text>(countLabel).data!;

  testWidgets('Ctrl+F opens the bar with the field focused', (tester) async {
    await pumpView(tester);
    expect(searchField, findsNothing);

    await openSearch(tester);
    expect(searchField, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: searchField, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    for (final tip in [
      'Use regex',
      'Previous match (Shift+Enter)',
      'Next match (Enter)',
      'Close search (Escape)',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
  });

  testWidgets('typing searches; next / previous buttons cycle the matches', (
    tester,
  ) async {
    await pumpView(tester);
    await openSearch(tester);

    await tester.enterText(searchField, 'hello');
    await tester.pump();
    expect(count(tester), '1 of 2');

    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pumpAndSettle();
    expect(count(tester), '2 of 2');

    await tester.tap(find.byTooltip('Next match (Enter)'));
    await tester.pumpAndSettle();
    expect(count(tester), '1 of 2');

    await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
    await tester.pumpAndSettle();
    expect(count(tester), '2 of 2');
  });

  testWidgets('Enter / Shift+Enter in the field step through the matches', (
    tester,
  ) async {
    await pumpView(tester);
    await openSearch(tester);
    await tester.enterText(searchField, 'hello');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(count(tester), '2 of 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(count(tester), '1 of 2');
  });

  testWidgets('no results and invalid regex are reported', (tester) async {
    await pumpView(tester);
    await openSearch(tester);

    await tester.enterText(searchField, 'zzz');
    await tester.pump();
    expect(count(tester), 'No results');

    await tester.tap(find.byTooltip('Use regex'));
    await tester.pumpAndSettle();
    await tester.enterText(searchField, '(');
    await tester.pump();
    expect(count(tester), 'Invalid regex');

    await tester.enterText(searchField, 'h.llo');
    await tester.pump();
    expect(count(tester), '1 of 2');
  });

  testWidgets('Escape in the field closes the search', (tester) async {
    await pumpView(tester);
    await openSearch(tester);
    await tester.enterText(searchField, 'hello');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(searchField, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TerminalView>(),
      isNotNull,
      reason: 'the terminal takes typing again after the search closes',
    );
  });

  testWidgets('the close button closes the search', (tester) async {
    await pumpView(tester);
    await openSearch(tester);

    await tester.tap(find.byTooltip('Close search (Escape)'));
    await tester.pumpAndSettle();
    expect(searchField, findsNothing);
  });
}
