import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/terminal_side_panel.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

Future<void> _open(
  WidgetTester t, {
  void Function(TerminalKey, {bool ctrl, bool alt})? onKey,
  int initialTab = 0,
}) async {
  t.view.physicalSize = const Size(360, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
        ChangeNotifierProvider(create: (_) => SnippetProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: ysTestApp(
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showTerminalSidePanel(
                ctx,
                sessionId: 's1',
                onInsert: (_) {},
                onKey: onKey ?? (k, {ctrl = false, alt = false}) {},
                initialTab: initialTab,
              ),
              child: const Text('open'),
            ),
          ),
        ),
        touch: true,
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the four tabs on forui FTabs', (t) async {
    await _open(t);
    expect(find.byType(FTabs), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Themes'), findsOneWidget);
  });

  testWidgets('keys grid: every key is an FButton >= 44 px and emits its key',
      (t) async {
    final got = <TerminalKey>[];
    await _open(t, onKey: (k, {ctrl = false, alt = false}) => got.add(k));
    expect(find.byType(FButton), findsNWidgets(20));
    for (final e in find.byType(FButton).evaluate()) {
      final size = t.getSize(find.byWidget(e.widget));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
    await t.tap(find.text('PgUp'));
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('F10'));
    await t.pump(const Duration(milliseconds: 150));
    expect(got, [TerminalKey.pageUp, TerminalKey.f10]);
  });

  testWidgets('snippets search + empty states for snippets and history', (t) async {
    await _open(t);
    await t.tap(find.text('Snippets'));
    await t.pumpAndSettle();
    expect(find.byType(FTextField), findsOneWidget);
    await t.enterText(find.byType(EditableText), 'zzz-no-such-snippet');
    await t.pumpAndSettle();
    expect(find.text('No snippets'), findsOneWidget);
    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(find.text('No command history yet'), findsOneWidget);
  });

  testWidgets('side-panel key does not move focus off the previous focus',
      (t) async {
    final node = FocusNode(debugLabel: 'prior');
    addTearDown(node.dispose);
    final got = <TerminalKey>[];
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
          ChangeNotifierProvider(create: (_) => SnippetProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: ysTestApp(
          Builder(
            builder: (ctx) => Column(children: [
              Focus(focusNode: node, child: const SizedBox(height: 40)),
              ElevatedButton(
                onPressed: () => showTerminalSidePanel(ctx,
                    sessionId: 's1',
                    onInsert: (_) {},
                    onKey: (k, {ctrl = false, alt = false}) => got.add(k)),
                child: const Text('open'),
              ),
            ]),
          ),
          touch: true,
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final before = FocusManager.instance.primaryFocus;
    await t.tap(find.text('PgUp'));
    await t.pump(const Duration(milliseconds: 150));
    expect(got, [TerminalKey.pageUp]);
    // Recorded: where focus sits after the tap (must not be a key button).
    final after = FocusManager.instance.primaryFocus;
    expect(after, before, reason: 'PgUp tap moved focus');
  });
}
