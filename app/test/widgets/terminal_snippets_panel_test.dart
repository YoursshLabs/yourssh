import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/widgets/broadcast_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/terminal_snippets_panel.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../helpers/ys_test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap({
    required bool canRun,
    required void Function(Snippet) onRunSnippet,
  }) {
    return ChangeNotifierProvider(
      create: (_) => SnippetProvider(),
      child: ysTestApp(
        TerminalSnippetsPanel(
          canRun: canRun,
          onRunSnippet: onRunSnippet,
        ),
      ),
    );
  }

  testWidgets('renders snippets from provider', (tester) async {
    await tester.pumpWidget(wrap(canRun: true, onRunSnippet: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('Disk usage'), findsOneWidget);
    expect(find.text('Memory info'), findsOneWidget);
  });

  testWidgets('search filters snippet rows', (tester) async {
    await tester.pumpWidget(wrap(canRun: true, onRunSnippet: (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(FTextField), 'memory');
    await tester.pump();

    expect(find.text('Memory info'), findsOneWidget);
    expect(find.text('Disk usage'), findsNothing);
  });

  testWidgets('run action forwards selected snippet', (tester) async {
    String? command;

    await tester.pumpWidget(
      wrap(
        canRun: true,
        onRunSnippet: (snippet) => command = snippet.command,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Run snippet').first);
    await tester.pumpAndSettle();

    expect(command, 'df -h');
  });

  testWidgets('run action is disabled when canRun is false', (tester) async {
    String? command;

    await tester.pumpWidget(
      wrap(
        canRun: false,
        onRunSnippet: (snippet) => command = snippet.command,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Run snippet').first);
    await tester.pumpAndSettle();

    expect(command, isNull);
    expect(find.text('No active SSH pane selected'), findsOneWidget);
  });

  testWidgets('keyboard flow: Tab from search reaches Run, Enter runs it',
      (tester) async {
    String? command;
    await tester.pumpWidget(
      wrap(canRun: true, onRunSnippet: (s) => command = s.command),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FTextField));
    await tester.pump();
    await tester.enterText(find.byType(FTextField), 'disk');
    await tester.pump();
    expect(find.text('Disk usage'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(command, 'df -h');
  });

  testWidgets('Run and Copy keep their text labels', (tester) async {
    await tester.pumpWidget(wrap(canRun: true, onRunSnippet: (_) {}));
    await tester.pumpAndSettle();
    expect(find.text('Run'), findsWidgets);
    expect(find.text('Copy'), findsWidgets);
  });

  testWidgets('groups follow first-seen tag order, untagged last, 40 tags',
      (tester) async {
    tester.view.physicalSize = const Size(600, 40000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Descending tag names, so alphabetical order would differ from
    // first-seen order; an untagged snippet comes first in the input.
    final seeded = <Snippet>[
      Snippet(label: 'plain', command: 'echo plain'),
      for (var i = 39; i >= 0; i--)
        for (final p in ['a', 'b'])
          Snippet(
            label: '$p-tag${i.toString().padLeft(2, '0')}',
            command: 'c',
            tag: 'tag${i.toString().padLeft(2, '0')}',
          ),
    ];
    SharedPreferences.setMockInitialValues({
      'yourssh.snippets': jsonEncode(seeded.map((e) => e.toJson()).toList()),
    });
    final provider = SnippetProvider();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: ysTestApp(
          TerminalSnippetsPanel(canRun: true, onRunSnippet: (_) {})),
    ));
    await tester.pumpAndSettle();

    final tagTexts = tester
        .widgetList<Text>(find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').startsWith('tag')))
        .map((t) => t.data!)
        .toList();
    expect(tagTexts, [
      for (var i = 39; i >= 0; i--) 'tag${i.toString().padLeft(2, '0')}',
    ]);
    // Provider order preserved inside a group, untagged group last.
    final ys = (String l) => tester.getTopLeft(find.text(l)).dy;
    expect(ys('a-tag39'), lessThan(ys('b-tag39')));
    expect(ys('plain'), greaterThan(ys('b-tag00')));
  });

  testWidgets('toolbar toggle controls snippets panel visibility', (tester) async {
    final layout = TerminalLayoutProvider();
    // The toolbar only shows the snippets button when the plugin is enabled.
    SharedPreferences.setMockInitialValues({
      'enabled_plugins': [YourSSHSnippetsPlugin.pluginId],
    });
    final plugins = PluginProvider(plugins: [YourSSHSnippetsPlugin()]);
    await plugins.loadFromPrefs();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TerminalLayoutProvider>.value(value: layout),
          ChangeNotifierProvider<PluginProvider>.value(value: plugins),
        ],
        child: ysTestApp(const BroadcastToolbar()),
      ),
    );

    expect(layout.snippetsPanelVisible, false);

    await tester.tap(find.byTooltip('Toggle Snippets Panel'));
    await tester.pumpAndSettle();

    expect(layout.snippetsPanelVisible, true);
  });
}
