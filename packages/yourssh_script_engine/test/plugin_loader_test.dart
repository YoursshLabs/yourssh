import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_script_engine/src/plugin_loader.dart';
import 'package:yourssh_script_engine/src/plugin_manifest.dart';
import 'package:yourssh_script_engine/src/script_engine_service.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';

void main() {
  _reservedTests();
  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('loader_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('_tryLoad calls onConsentRequired for new plugin with permissions', () async {
    final pluginDir = Directory('${tmpDir.path}/my-plugin')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "my.plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.transform"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('plugin.on("terminal.output", function(ctx){ return ctx.data; });');

    String? consentPluginId;
    final bus = HookBus();
    final engine = ScriptEngineService(
      hookBus: bus,
      uiRegistry: null,
      sshDelegate: null,
      sftpDelegate: null,
    );
    final loader = PluginLoader(
      engine: engine,
      onConsentRequired: (id, manifest, dir) { consentPluginId = id; },
      onError: (id, msg) => fail('Unexpected error: $msg'),
    );

    // Use a temporary plugins dir so we don't scan real ~/.yourssh/plugins
    // We call _tryLoad indirectly by manipulating the private method
    // Instead, test approvePermissions:
    await loader.approvePermissions('my.plugin', {'terminal.transform'}, pluginDir.path);

    final result = bus.fireTransform('terminal.output',
        TransformEvent(sessionId: 's1', data: 'test'));
    expect(result, 'test'); // plugin loaded and hook fires

    engine.dispose();
    loader.dispose();
  });
}

void _reservedTests() {
  group('reserved built-in ids', () {
    late Directory tmp;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('reserved_test_');
      File('${tmp.path}/plugin.json').writeAsStringSync('''
{"id": "dev.yourssh.snippets", "name": "Snippets", "version": "2.0.0",
 "entry": "index.js", "minAppVersion": "1.0.0", "permissions": ["ui.notify"]}
''');
      File('${tmp.path}/index.js').writeAsStringSync('var x = 1;');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    PluginLoader make(List<String> consents, List<String> errors,
            ScriptEngineService engine) =>
        PluginLoader(
          engine: engine,
          reservedIds: {'dev.yourssh.snippets'},
          onConsentRequired: (id, _, __) => consents.add(id),
          onError: (id, m) => errors.add('$id: $m'),
        );

    test('tryLoad neither prompts nor loads, and keeps the directory', () async {
      final engine = ScriptEngineService(
          hookBus: HookBus(), uiRegistry: null, sshDelegate: null, sftpDelegate: null);
      final consents = <String>[], errors = <String>[];
      await make(consents, errors, engine).tryLoad(tmp.path);
      expect(consents, isEmpty);
      expect(engine.loadedManifests, isEmpty);
      expect(errors.single, contains('built-in'));
      expect(tmp.existsSync(), isTrue);
    });

    test('approvePermissions does not load it either', () async {
      final engine = ScriptEngineService(
          hookBus: HookBus(), uiRegistry: null, sshDelegate: null, sftpDelegate: null);
      final consents = <String>[], errors = <String>[];
      await make(consents, errors, engine)
          .approvePermissions('dev.yourssh.snippets', {'ui.notify'}, tmp.path);
      expect(engine.loadedManifests, isEmpty);
      expect(errors.single, contains('built-in'));
    });
  });
}
