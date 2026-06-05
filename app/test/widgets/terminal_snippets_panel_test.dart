import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/widgets/broadcast_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/terminal_snippets_panel.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

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
      child: MaterialApp(
        home: Scaffold(
          body: TerminalSnippetsPanel(
            canRun: canRun,
            onRunSnippet: onRunSnippet,
          ),
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

    await tester.enterText(find.byType(TextField), 'memory');
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
    await tester.pump();

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
    await tester.pump();

    expect(command, isNull);
    expect(find.text('No active SSH pane selected'), findsOneWidget);
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
        child: const MaterialApp(
          home: Scaffold(
            body: BroadcastToolbar(),
          ),
        ),
      ),
    );

    expect(layout.snippetsPanelVisible, false);

    await tester.tap(find.byTooltip('Toggle Snippets Panel'));
    await tester.pump();

    expect(layout.snippetsPanelVisible, true);
  });
}
