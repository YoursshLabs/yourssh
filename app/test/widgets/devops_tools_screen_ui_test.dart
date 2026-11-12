import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/devops_tools_screen.dart';

import '../helpers/fake_devops_ssh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeDevopsSsh> pump(
    WidgetTester tester, {
    bool withSession = true,
    String username = 'u',
  }) async {
    final fake = FakeDevopsSsh(
      reply: (_) => (stdout: 'pong output', stderr: '', exitCode: 0),
    );
    await tester.pumpWidget(devopsHarness(const DevopsToolsScreen(), fake,
        withSession: withSession, username: username));
    await tester.pump();
    return fake;
  }

  testWidgets('smoke: sidebar sections, input and run button', (tester) async {
    await pump(tester);
    for (final s in ['NETWORK', 'SYSTEM', 'HTTP']) {
      expect(find.text(s), findsOneWidget);
    }
    for (final t in [
      'Ping', 'cURL', 'DNS Lookup', 'Traceroute', 'Port Scan', 'Whois',
      'Netstat', 'Disk Usage', 'Top Processes', 'Memory Info',
      'HTTP Headers', 'SSL Certificate',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byKey(const ValueKey('devops-input')), findsOneWidget);
    expect(find.text('8.8.8.8'), findsOneWidget);
    expect(find.text('Run a tool to see output'), findsOneWidget);
    expect(find.byTooltip('Clear all tabs'), findsNothing);
    expect(find.text('No active session — connect to a host first'),
        findsNothing);
  });

  testWidgets('without a session shows the warning and run does nothing',
      (tester) async {
    final fake = await pump(tester, withSession: false);
    expect(find.text('No active session — connect to a host first'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('devops-run')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fake.cmds, isEmpty);
  });

  testWidgets('selecting a tool swaps the default input; no-input tools hide it',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('cURL'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com'), findsOneWidget);
    await tester.tap(find.text('Disk Usage'));
    await tester.pumpAndSettle();
    expect(find.text('/'), findsOneWidget);
    await tester.tap(find.text('Netstat'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('devops-input')), findsNothing);
  });

  testWidgets('Enter in the input runs; tab shows, switches and closes',
      (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('devops-input')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fake.cmds, hasLength(1));
    expect(fake.cmds.single, contains('8.8.8.8'));
    expect(find.text('Ping 8.8.8.8'), findsOneWidget);
    expect(find.byTooltip('Clear all tabs'), findsOneWidget);
    expect(find.textContaining('pong output'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('devops-run')));
    await tester.pumpAndSettle();
    expect(fake.cmds, hasLength(2));
    expect(find.text('Ping 8.8.8.8'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Close tab').last);
    await tester.pumpAndSettle();
    expect(find.text('Ping 8.8.8.8'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear all tabs'));
    await tester.pumpAndSettle();
    expect(find.text('Ping 8.8.8.8'), findsNothing);
    expect(find.text('Run a tool to see output'), findsOneWidget);
  });

  testWidgets('keyboard: Enter on the focused run button runs', (tester) async {
    final fake = await pump(tester);
    Focus.of(tester.element(find.descendant(
            of: find.byKey(const ValueKey('devops-run')),
            matching: find.byType(Icon))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds, hasLength(1));
  });

  testWidgets('900x600 with a 60-char input and many tabs does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, username: 'u' * 60);
    await tester.enterText(
        find.byKey(const ValueKey('devops-input')), 'h' * 60);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('devops-run')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
