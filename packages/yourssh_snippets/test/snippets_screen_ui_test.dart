import 'package:flutter/services.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_snippets/src/screens/snippets_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'helpers/tab_to.dart';
import 'helpers/ys_test_app.dart';

class _Ctx implements YourSSHPluginContext {
  String? sent;
  @override
  List<SSHSessionProxy> get activeSessions => const [
    SSHSessionProxy(
      sessionId: 's1',
      hostLabel: 'root@x',
      isConnected: true,
      isActive: true,
    ),
  ];
  @override
  SSHSessionProxy? get activeSession => activeSessions.first;
  @override
  Future<String> execCommand(String sessionId, String command) async => '';
  @override
  Future<String?> getPreference(String key) async => null;
  @override
  Future<void> savePreference(String key, String value) async {}
  @override
  Future<void> sendInput(String sessionId, String text) async => sent = text;
}

Widget _screen(SnippetProvider p, _Ctx c) => ChangeNotifierProvider.value(
  value: p,
  child: SnippetsScreen(pluginContext: c),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders main actions inside ysTestApp', (tester) async {
    await tester.pumpWidget(ysTestApp(_screen(SnippetProvider(), _Ctx())));
    await tester.pumpAndSettle();
    expect(find.text('NEW SNIPPET'), findsOneWidget);
    expect(find.text('Disk usage'), findsOneWidget);
    expect(find.byType(FTextField), findsOneWidget);
  });

  testWidgets('plugin root finds the Ys FTheme when pushed as a route', (
    tester,
  ) async {
    final plugin = YourSSHSnippetsPlugin();
    final provider = SnippetProvider();
    final ctx = _Ctx();
    late BuildContext inner;
    await pumpPushedRoute(
      tester,
      (c) => ChangeNotifierProvider.value(
        value: provider,
        child: Builder(
          builder: (c2) {
            inner = c2;
            return plugin.buildUI(c2, ctx);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final themed = tester.element(find.text('NEW SNIPPET'));
    expect(FTheme.of(themed).colors.primary, YsColors.primary);
    expect(inner.mounted, isTrue);
    expect(find.text('NEW SNIPPET'), findsOneWidget);
  });

  testWidgets('no overflow at 900x600 with a 60-char label', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = SnippetProvider();
    await tester.pumpWidget(ysTestApp(_screen(p, _Ctx())));
    await tester.pumpAndSettle();
    await p.add(
      Snippet(
        label: 'L' * 60,
        command: 'echo ${'c' * 60}',
        description: 'd' * 60,
        tag: 't' * 60,
      ),
    );
    await tester.pumpAndSettle();
    // Open the panel too: list + 340 px panel is the narrowest layout.
    await tester.tap(find.text('NEW SNIPPET'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab reaches NEW SNIPPET and Enter opens the panel', (
    tester,
  ) async {
    await tester.pumpWidget(ysTestApp(_screen(SnippetProvider(), _Ctx())));
    await tester.pumpAndSettle();
    expect(await tabTo(tester, find.text('NEW SNIPPET')), greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('New Snippet'), findsOneWidget);
  });

  testWidgets('add snippet through the panel, validate required fields', (
    tester,
  ) async {
    final p = SnippetProvider();
    await tester.pumpWidget(ysTestApp(_screen(p, _Ctx())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NEW SNIPPET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Snippet'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const ValueKey('snippet-label')),
      'Hello',
    );
    await tester.enterText(
      find.byKey(const ValueKey('snippet-command')),
      'echo hi',
    );
    await tester.tap(find.text('Add Snippet'));
    await tester.pumpAndSettle();
    expect(
      p.snippets.any((s) => s.label == 'Hello' && s.command == 'echo hi'),
      isTrue,
    );
    expect(find.text('New Snippet'), findsNothing);
  });

  testWidgets('search filters the list; row actions reachable by Tab', (
    tester,
  ) async {
    final ctx = _Ctx();
    await tester.pumpWidget(ysTestApp(_screen(SnippetProvider(), ctx)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'ports');
    await tester.pumpAndSettle();
    expect(find.text('Open ports'), findsOneWidget);
    expect(find.text('Disk usage'), findsNothing);
    // Row actions are keyboard reachable without hovering.
    expect(
      await tabTo(tester, find.byTooltip('Run in terminal')),
      greaterThan(0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ctx.sent, 'ss -tlnp\n');
  });

  testWidgets('hidden row actions are inert and absent from semantics', (
    tester,
  ) async {
    final p = SnippetProvider();
    final ctx = _Ctx();
    await tester.pumpWidget(ysTestApp(_screen(p, ctx)));
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Delete'), findsNothing);
    expect(find.bySemanticsLabel('Run in terminal'), findsNothing);
    final before = p.snippets.length;
    await tester.tap(find.byTooltip('Delete').first, warnIfMissed: false);
    await tester.tap(
      find.byTooltip('Run in terminal').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(p.snippets.length, before);
    expect(ctx.sent, isNull);
    // Focus reveals them (semantics return) and Enter still activates.
    expect(
      await tabTo(tester, find.byTooltip('Run in terminal')),
      greaterThan(0),
    );
    expect(find.bySemanticsLabel('Run in terminal'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(ctx.sent, 'df -h\n');
    handle.dispose();
  });
}
