import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/screens/shell/app_sidebar.dart';
import 'package:yourssh/services/update_service.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakePlugin extends YourSSHPlugin {
  @override
  String get id => 'dev.test.fake';
  @override
  String get name => 'Fake Plugin';
  @override
  String get description => '';
  @override
  IconData get icon => Icons.extension;
  @override
  String get version => '1.0.0';
  @override
  String get minApiVersion => '1.0.0';
  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) =>
      const SizedBox();
}

/// Taps a label and lets forui's press timers drain.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late PluginProvider plugins;
  late PluginUiRegistry registry;
  late UpdateProvider update;

  Future<void> pump(
    WidgetTester tester, {
    NavSection selected = NavSection.hosts,
    String? activePluginId,
    String? activeScriptPanel,
    ValueChanged<NavSection>? onSelect,
    ValueChanged<String>? onSelectPlugin,
    ValueChanged<String>? onSelectScriptPanel,
    VoidCallback? onOpenLocalTerminal,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    plugins = PluginProvider(plugins: [_FakePlugin()]);
    await plugins.toggle('dev.test.fake');
    registry = PluginUiRegistry()
      ..addPanel(
        PluginPanelEntry(
          pluginId: 'js.panel',
          title: 'JS Panel',
          icon: 'code',
          webviewEntry: 'index.html',
          onMessage: (_) async => null,
        ),
      );
    update = UpdateProvider(UpdateService(), currentVersion: '1.2.3');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PluginProvider>.value(value: plugins),
          ChangeNotifierProvider<PluginUiRegistry>.value(value: registry),
          ChangeNotifierProvider<UpdateProvider>.value(value: update),
        ],
        child: ysTestApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: AppSidebar(
                selected: selected,
                activePluginId: activePluginId,
                activeScriptPanel: activeScriptPanel,
                onSelect: onSelect ?? (_) {},
                onSelectPlugin: onSelectPlugin ?? (_) {},
                onSelectScriptPanel: onSelectScriptPanel ?? (_) {},
                onOpenLocalTerminal: onOpenLocalTerminal ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('every nav label is present exactly once', (tester) async {
    await pump(tester);
    for (final label in const [
      'Hosts',
      'Keychain',
      'Port Forwarding',
      'SFTP',
      'Known Hosts',
      'Recordings',
      'Audit Log',
      'Settings',
      'Plugins',
      'Local Terminal',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final group in const [
      'Connections',
      'Files & Transfer',
      'Tools',
      'Security',
    ]) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    expect(find.text('YourSSH'), findsOneWidget);
    expect(find.textContaining('v1.2.3'), findsOneWidget);
  });

  testWidgets('tapping a nav item calls onSelect with its section', (
    tester,
  ) async {
    NavSection? got;
    await pump(tester, onSelect: (s) => got = s);
    await tapText(tester, 'Known Hosts');
    expect(got, NavSection.knownHosts);
    await tapText(tester, 'Settings');
    expect(got, NavSection.settings);
    await tapText(tester, 'Plugins');
    expect(got, NavSection.plugins);
  });

  testWidgets('Local Terminal is an action, not a nav target', (tester) async {
    var opened = 0;
    NavSection? got;
    await pump(
      tester,
      onOpenLocalTerminal: () => opened++,
      onSelect: (s) => got = s,
    );
    await tapText(tester, 'Local Terminal');
    expect(opened, 1);
    expect(got, isNull);
  });

  testWidgets('plugin and script-panel items render and fire callbacks', (
    tester,
  ) async {
    String? plugin;
    String? panel;
    await pump(
      tester,
      onSelectPlugin: (id) => plugin = id,
      onSelectScriptPanel: (id) => panel = id,
    );
    expect(find.text('Fake Plugin'), findsOneWidget);
    expect(find.text('JS Panel'), findsOneWidget);
    await tapText(tester, 'Fake Plugin');
    await tapText(tester, 'JS Panel');
    expect(plugin, 'dev.test.fake');
    expect(panel, 'js.panel');
  });

  testWidgets('selected item uses the primary colour, others do not', (
    tester,
  ) async {
    await pump(tester, selected: NavSection.hosts);
    Color labelColor(String text) =>
        DefaultTextStyle.of(tester.element(find.text(text))).style.color!;
    expect(labelColor('Hosts'), YsColors.primary);
    expect(labelColor('Known Hosts'), isNot(YsColors.primary));
  });

  testWidgets('an active plugin deselects the nav section', (tester) async {
    await pump(
      tester,
      selected: NavSection.hosts,
      activePluginId: 'dev.test.fake',
    );
    Color labelColor(String text) =>
        DefaultTextStyle.of(tester.element(find.text(text))).style.color!;
    expect(labelColor('Hosts'), isNot(YsColors.primary));
    expect(labelColor('Fake Plugin'), YsColors.primary);
  });

  testWidgets('Tab traverses the nav items in visual order', (tester) async {
    await pump(tester);
    final seen = <String>[];
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final item = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<FSidebarItem>();
      final label = item?.label;
      if (label is Text) seen.add(label.data!);
    }
    expect(seen, [
      'Hosts',
      'Port Forwarding',
      'Known Hosts',
      'SFTP',
      'Local Terminal',
      'Recordings',
      'Audit Log',
      'Fake Plugin',
      'JS Panel',
      'Keychain',
      'Plugins',
      'Settings',
    ]);
  });

  testWidgets('sidebar renders 200 px wide', (tester) async {
    await pump(tester);
    expect(tester.getSize(find.byType(FSidebar)).width, 200);
  });

  testWidgets('brand header does not overflow at text scale 2.0', (
    tester,
  ) async {
    await pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
    final brand = find.text('YourSSH');
    expect(brand, findsOneWidget);
    expect(
      tester.getBottomRight(brand).dx,
      lessThanOrEqualTo(tester.getSize(find.byType(FSidebar)).width),
    );
  });
}
