import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/plugin_engine_provider.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/widgets/plugin_manager_screen.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

final _long = 'L' * 60;

class _FakePlugin extends YourSSHPlugin {
  @override
  final String id;
  @override
  final String name;
  _FakePlugin(this.id, this.name);
  @override
  String get description => 'Description of $name';
  @override
  IconData get icon => FLucideIcons.puzzle;
  @override
  String get version => '1.0.0';
  @override
  String get minApiVersion => '1.0.0';
  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) =>
      const SizedBox();
}

class _EngineProvider extends PluginEngineProvider {
  final List<PluginManifest> manifests;
  _EngineProvider(this.manifests, {required super.engine, required super.loader, required super.hookBus, required super.uiRegistry});

  @override
  List<PluginManifest> get loadedPlugins => manifests;
}

_EngineProvider _engine(List<PluginManifest> manifests) {
  final bus = HookBus();
  final registry = PluginUiRegistry();
  final engine = ScriptEngineService(
    hookBus: bus,
    uiRegistry: registry,
    sshDelegate: null,
    sftpDelegate: null,
  );
  final loader = PluginLoader(
    engine: engine,
    onConsentRequired: (_, _, _) {},
    onError: (_, _) {},
  );
  return _EngineProvider(
    manifests,
    engine: engine,
    loader: loader,
    hookBus: bus,
    uiRegistry: registry,
  );
}

PluginManifest _m(String id, String name) => PluginManifest(
  id: id,
  name: name,
  version: '1.0.0',
  entry: 'index.js',
  minAppVersion: '1.0.0',
  permissions: const {'ui.notify'},
);

Widget _host(PluginEngineProvider e, PluginProvider p) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PluginEngineProvider>.value(value: e),
        ChangeNotifierProvider<PluginProvider>.value(value: p),
      ],
      child: ysTestApp(const PluginManagerScreen()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows both sections, empty hints and the drop-folder help', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_engine([]), PluginProvider(plugins: [])),
    );
    expect(find.text('BUILT-IN PLUGINS'), findsOneWidget);
    expect(find.text('SCRIPT PLUGINS'), findsOneWidget);
    expect(find.text('No built-in plugins registered.'), findsOneWidget);
    expect(find.text('No script plugins loaded.'), findsOneWidget);
    expect(find.textContaining('~/.yourssh/plugins/'), findsOneWidget);
  });

  testWidgets('a built-in plugin row toggles by tapping the switch', (
    tester,
  ) async {
    final plugins = PluginProvider(plugins: [_FakePlugin('a.b', 'Alpha')]);
    await tester.pumpWidget(_host(_engine([]), plugins));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Description of Alpha'), findsOneWidget);
    expect(plugins.isEnabled('a.b'), isFalse);

    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    expect(plugins.isEnabled('a.b'), isTrue);
  });

  testWidgets('pending consent card offers Review', (tester) async {
    final engine = _engine([]);
    engine.setPendingConsent('x', _m('x', 'Newbie'), '/p/x');
    await tester.pumpWidget(
      _host(engine, PluginProvider(plugins: [])),
    );
    expect(find.text('New plugin: Newbie'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Install "Newbie"'), findsOneWidget);
  });

  testWidgets('script plugin row opens its logs via the View logs button', (
    tester,
  ) async {
    final engine = _engine([_m('dev.x', 'Scripty')]);
    engine.addLog('dev.x', 'hello log');
    await tester.pumpWidget(_host(engine, PluginProvider(plugins: [])));
    expect(find.text('Scripty'), findsOneWidget);
    expect(find.text('dev.x  •  v1.0.0'), findsOneWidget);
    expect(find.byTooltip('View logs'), findsOneWidget);

    await tester.tap(find.byTooltip('View logs'));
    await tester.pumpAndSettle();
    expect(find.text('hello log'), findsOneWidget);
  });

  testWidgets('60-char names do not overflow at 900x600', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = _engine([_m('d' * 60, _long)]);
    engine.setPendingConsent('x', _m('x', _long), '/p/x');
    final plugins = PluginProvider(plugins: [_FakePlugin('e' * 60, _long)]);
    await tester.pumpWidget(_host(engine, plugins));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
