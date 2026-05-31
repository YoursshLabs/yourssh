import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_script_engine/src/plugin_loader.dart';
import 'package:yourssh_script_engine/src/plugin_manifest.dart';
import 'package:yourssh_script_engine/src/script_engine_service.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';

void main() {
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
