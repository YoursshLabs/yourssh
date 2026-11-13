import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/mail_catcher_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show FButton;

import '../helpers/fake_devops_ssh.dart';
import '../helpers/tab_to_control.dart';

String _smtpdLog(String subject, String from) => '''
---------- MESSAGE FOLLOWS ----------
Subject: $subject
From: $from
To: bob@example.com
X-Peer: 127.0.0.1

hello body

second para
------------ END MESSAGE ------------
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeDevopsSsh> pump(
    WidgetTester tester, {
    bool withSession = true,
    String subject = 'Welcome',
    String from = 'alice@example.com',
    bool startOk = true,
    double textScale = 1,
  }) async {
    final fake = FakeDevopsSsh();
    var cleared = false;
    fake.reply = (cmd) {
      if (cmd.startsWith('> ')) {
        cleared = true;
        return (stdout: '', stderr: '', exitCode: 0);
      }
      if (cmd.contains('mktemp')) {
        return (
          stdout: startOk ? 'started:/tmp/mc1' : 'ERR:exited:/tmp/mc1',
          stderr: '',
          exitCode: 0,
        );
      }
      if (cmd.startsWith('cat ')) {
        return (
          stdout: cleared ? '' : _smtpdLog(subject, from),
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    await tester.pumpWidget(
      devopsHarness(
        Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: const MailCatcherScreen(),
          ),
        ),
        fake,
        withSession: withSession,
      ),
    );
    await tester.pump();
    return fake;
  }

  Future<void> stopAndDispose(WidgetTester tester) async {
    if (find.byTooltip('Stop').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('smoke: title, start, empty list and empty detail',
      (tester) async {
    await pump(tester);
    expect(find.text('Mail Catcher'), findsOneWidget);
    expect(find.byTooltip('Start on port 1025'), findsOneWidget);
    expect(find.text('No emails captured'), findsOneWidget);
    expect(find.text('Select an email'), findsOneWidget);
    expect(find.byTooltip('Clear all'), findsNothing);
  });

  testWidgets('list header shows the full title while there is room',
      (tester) async {
    // The test font is much wider than Inter: scale it so the title fits in
    // the 260 px column next to the badge and icons (as it does in the app).
    await pump(tester, textScale: 0.6);
    await tester.tap(find.byTooltip('Start on port 1025'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    // Count badge + clear + stop icons are all showing.
    expect(find.text('1'), findsOneWidget);
    expect(find.byTooltip('Clear all'), findsOneWidget);
    final title = tester.renderObject<RenderParagraph>(find.text('Mail Catcher'));
    expect(title.didExceedMaxLines, isFalse, reason: 'title was ellipsized');
    await stopAndDispose(tester);
  });

  testWidgets('start, poll, select, clear, stop', (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.byTooltip('Start on port 1025'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Listening on :1025'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.textContaining('alice@example.com'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('Welcome'));
    await tester.pump();
    expect(find.text('Subject: Welcome'), findsOneWidget);
    expect(find.text('From: alice@example.com'), findsOneWidget);
    expect(find.text('To: bob@example.com'), findsOneWidget);
    expect(find.textContaining('hello body'), findsOneWidget);
    expect(find.textContaining('second para'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Clear'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No emails captured'), findsOneWidget);
    expect(find.text('Select an email'), findsOneWidget);
    expect(fake.cmds.any((c) => c.startsWith("> ") && c.contains('mc1/log')),
        isTrue);
    // The next poll must not bring the cleared mail back.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('No emails captured'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(find.byTooltip('Start on port 1025'), findsOneWidget);
    expect(find.text('Listening on :1025'), findsNothing);
    expect(fake.cmds.any((c) => c.startsWith('kill ')), isTrue);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Clear all failure shows a toast and keeps the list',
      (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.byTooltip('Start on port 1025'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Welcome'), findsOneWidget);
    final inner = fake.reply!;
    fake.reply = (cmd) {
      if (cmd.startsWith('> ')) throw StateError('ssh down');
      return inner(cmd);
    };
    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Clear'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("Couldn't clear the mail log:"), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    await stopAndDispose(tester);
  });

  testWidgets('Clear all asks first; Cancel keeps the mails and the log',
      (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.byTooltip('Start on port 1025'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Welcome'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear captured mail?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clear captured mail?'), findsNothing);
    expect(find.text('Welcome'), findsOneWidget);
    expect(fake.cmds.any((c) => c.startsWith('> ')), isFalse,
        reason: 'cancel must not truncate the remote log');
    await stopAndDispose(tester);
  });

  testWidgets('failed start shows the error toast', (tester) async {
    await pump(tester, startOk: false);
    await tester.tap(find.byTooltip('Start on port 1025'));
    await tester.pumpAndSettle();
    expect(find.text('Failed to start SMTP server. Ensure python3 is installed.'),
        findsOneWidget);
    expect(find.text('Listening on :1025'), findsNothing);
  });

  testWidgets('without a session start is disabled', (tester) async {
    final fake = await pump(tester, withSession: false);
    await tester.tap(find.byTooltip('Start on port 1025'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fake.cmds, isEmpty);
  });

  testWidgets('keyboard: Enter on the focused start button starts',
      (tester) async {
    await pump(tester);
    Focus.of(tester.element(find.descendant(
            of: find.byTooltip('Start on port 1025'),
            matching: find.byType(Icon))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Listening on :1025'), findsOneWidget);
    await stopAndDispose(tester);
  });

  testWidgets('Tab reaches the start button in one press; Enter starts',
      (tester) async {
    await pump(tester);
    final n = await tabToControl(tester, find.byTooltip('Start on port 1025'));
    expect(n, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(find.text('Listening on :1025'), findsOneWidget);
    await stopAndDispose(tester);
  });

  testWidgets('900x600 with a 60-char subject and sender does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, subject: 'S' * 60, from: '${'f' * 60}@example.com');
    await tester.tap(find.byTooltip('Start on port 1025'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('S' * 60).first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await stopAndDispose(tester);
  });
}
