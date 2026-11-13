import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/mcp_server_screen.dart';

import '../helpers/fake_devops_ssh.dart';
import '../helpers/tab_to_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeDevopsSsh> pump(
    WidgetTester tester, {
    bool withSession = true,
    String username = 'u',
    String pid = '4242',
  }) async {
    final fake = FakeDevopsSsh(
      reply: (_) => (stdout: pid, stderr: '', exitCode: 0),
    );
    await tester.pumpWidget(devopsHarness(const McpServerScreen(), fake,
        withSession: withSession, username: username));
    await tester.pump();
    return fake;
  }

  testWidgets('smoke: heading, fields, start button and tips', (tester) async {
    await pump(tester);
    expect(find.text('MCP Server Gateway'), findsOneWidget);
    expect(find.text('MCP Server Command'), findsOneWidget);
    expect(find.text('Local Port'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-command')), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-port')), findsOneWidget);
    expect(find.text('npx @anthropic-ai/mcp-server'), findsWidgets);
    expect(find.text('9090'), findsOneWidget);
    expect(find.text('Start MCP Server'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('MCP Server Running'), findsNothing);
  });

  testWidgets('start runs the same command, shows endpoint, stop kills it',
      (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.text('Start MCP Server'));
    await tester.pumpAndSettle();
    expect(fake.cmds.single, contains('npx @anthropic-ai/mcp-server --port 18090'));
    expect(find.text('MCP Server Running'), findsOneWidget);
    expect(find.text('http://localhost:9090/mcp'), findsOneWidget);
    expect(find.byTooltip('Copy endpoint'), findsOneWidget);
    expect(find.text('Stop MCP Server'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byTooltip('Copy endpoint'));
    await tester.pump();
    expect(copied, 'http://localhost:9090/mcp');

    await tester.tap(find.text('Stop MCP Server'));
    await tester.pumpAndSettle();
    expect(fake.cmds.last, 'kill 4242 2>/dev/null');
    expect(find.text('Start MCP Server'), findsOneWidget);
    expect(find.text('MCP Server Running'), findsNothing);
  });

  testWidgets('invalid port shows the error toast and runs nothing',
      (tester) async {
    final fake = await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('mcp-port')), '70000');
    await tester.tap(find.text('Start MCP Server'));
    await tester.pumpAndSettle();
    expect(find.text('Port must be between 1 and 65535'), findsOneWidget);
    expect(fake.cmds, isEmpty);
  });

  testWidgets('failed start surfaces the error', (tester) async {
    final fake = await pump(tester, pid: 'nope');
    await tester.tap(find.text('Start MCP Server'));
    await tester.pumpAndSettle();
    expect(fake.cmds, hasLength(1));
    expect(find.textContaining('MCP start failed:'), findsOneWidget);
    expect(find.text('Start MCP Server'), findsOneWidget);
  });

  testWidgets('keyboard: Enter on the focused start button starts',
      (tester) async {
    final fake = await pump(tester);
    Focus.of(tester.element(find.text('Start MCP Server'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds, hasLength(1));
    expect(find.text('MCP Server Running'), findsOneWidget);
  });

  testWidgets('Tab reaches the start button (command, port, button); Enter starts',
      (tester) async {
    final fake = await pump(tester);
    final n = await tabToControl(tester, find.byKey(const ValueKey('mcp-toggle')));
    expect(n, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds, hasLength(1));
    expect(find.text('MCP Server Running'), findsOneWidget);
  });

  testWidgets('without a session the start button is disabled', (tester) async {
    final fake = await pump(tester, withSession: false);
    await tester.tap(find.text('Start MCP Server'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(fake.cmds, isEmpty);
  });

  testWidgets('900x600 with a 60-char host and long command does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, username: 'u' * 60);
    await tester.enterText(
        find.byKey(const ValueKey('mcp-command')), 'npx ${'x' * 60}');
    await tester.tap(find.text('Start MCP Server'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
