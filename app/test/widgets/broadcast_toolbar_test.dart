import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/widgets/broadcast_toolbar.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PluginProvider> pluginProvider({required bool snippetsEnabled}) async {
    SharedPreferences.setMockInitialValues({
      'enabled_plugins': snippetsEnabled ? [YourSSHSnippetsPlugin.pluginId] : <String>[],
    });
    final provider = PluginProvider(plugins: [YourSSHSnippetsPlugin()]);
    await provider.loadFromPrefs();
    return provider;
  }

  Widget wrap(TerminalLayoutProvider layout, PluginProvider plugins) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: layout),
        ChangeNotifierProvider.value(value: plugins),
      ],
      child: const MaterialApp(home: Scaffold(body: BroadcastToolbar())),
    );
  }

  testWidgets('tune button toggles the terminal config panel', (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout, await pluginProvider(snippetsEnabled: false)));

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, true);

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, false);
  });

  testWidgets('snippets button hidden when snippets plugin is disabled',
      (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout, await pluginProvider(snippetsEnabled: false)));

    expect(find.byTooltip('Toggle Snippets Panel'), findsNothing);
  });

  testWidgets('snippets button shown and toggles panel when plugin is enabled',
      (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout, await pluginProvider(snippetsEnabled: true)));

    expect(find.byTooltip('Toggle Snippets Panel'), findsOneWidget);

    await tester.tap(find.byTooltip('Toggle Snippets Panel'));
    await tester.pump();
    expect(layout.snippetsPanelVisible, true);
  });

  testWidgets('snippets button disappears when plugin is disabled live',
      (tester) async {
    final layout = TerminalLayoutProvider();
    final plugins = await pluginProvider(snippetsEnabled: true);
    await tester.pumpWidget(wrap(layout, plugins));

    expect(find.byTooltip('Toggle Snippets Panel'), findsOneWidget);

    await plugins.toggle(YourSSHSnippetsPlugin.pluginId);
    await tester.pump();
    expect(find.byTooltip('Toggle Snippets Panel'), findsNothing);
  });

  testWidgets('opening config panel from toolbar closes snippets panel',
      (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout, await pluginProvider(snippetsEnabled: true)));

    await tester.tap(find.byTooltip('Toggle Snippets Panel'));
    await tester.pump();
    expect(layout.snippetsPanelVisible, true);

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, true);
    expect(layout.snippetsPanelVisible, false);
  });
}
