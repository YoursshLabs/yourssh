import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';
import 'package:yourssh_script_engine/src/plugin_loader.dart';
import 'package:yourssh_script_engine/src/plugin_paths.dart';
import 'package:yourssh_script_engine/src/script_engine_service.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('plugin_sec_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  Directory writePlugin(
    String name, {
    String id = 'sec.plugin',
    String entry = 'index.js',
    List<String> perms = const ['terminal.transform'],
    String js = '',
  }) {
    final dir = Directory('${tmpDir.path}/$name')..createSync(recursive: true);
    File('${dir.path}/plugin.json').writeAsStringSync('''
{
  "id": "$id",
  "name": "Sec",
  "version": "1.0.0",
  "entry": "$entry",
  "minAppVersion": "1.0.0",
  "permissions": [${perms.map((p) => '"$p"').join(',')}]
}
''');
    if (!entry.startsWith('..') && !entry.startsWith('/')) {
      File('${dir.path}/$entry').writeAsStringSync(js);
    }
    return dir;
  }

  ScriptEngineService newEngine(HookBus bus,
          {void Function(String, String, String)? onLog}) =>
      ScriptEngineService(
        hookBus: bus,
        uiRegistry: null,
        sshDelegate: null,
        sftpDelegate: null,
        onLog: onLog,
      );

  group('execution limits', () {
    test('runaway hook times out, then the plugin is unloaded', () async {
      final dir = writePlugin('loop', js: '''
plugin.on("terminal.output", function(ctx) { while (true) {} });
''');
      final bus = HookBus();
      final logs = <String>[];
      final svc = newEngine(bus, onLog: (id, lvl, m) => logs.add('$lvl $m'));
      await svc.loadPlugin(dir.path,
          grantedPermissions: {'terminal.transform'});

      final sw = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        final out = bus.fireTransform(
            'terminal.output', TransformEvent(sessionId: 's', data: 'x'));
        expect(out, 'x');
      }
      expect(sw.elapsedMilliseconds, lessThan(5000));
      await Future<void>.delayed(Duration.zero);
      expect(svc.loadedManifests, isEmpty);
      expect(logs.any((l) => l.startsWith('error')), isTrue);
      svc.dispose();
    });

    test('plugin that keeps throwing is unloaded', () async {
      final dir = writePlugin('thrower', js: '''
plugin.on("terminal.output", function(ctx) { throw new Error("boom"); });
''');
      final bus = HookBus();
      final svc = newEngine(bus);
      await svc.loadPlugin(dir.path,
          grantedPermissions: {'terminal.transform'});
      for (var i = 0; i < 10; i++) {
        bus.fireTransform(
            'terminal.output', TransformEvent(sessionId: 's', data: 'x'));
      }
      await Future<void>.delayed(Duration.zero);
      expect(svc.loadedManifests, isEmpty);
      svc.dispose();
    });

    test('runaway top-level code fails the load', () async {
      final dir = writePlugin('loadloop', js: 'while(true){}');
      final svc = newEngine(HookBus());
      await expectLater(
          svc.loadPlugin(dir.path, grantedPermissions: {}), throwsException);
      expect(svc.loadedManifests, isEmpty);
      svc.dispose();
    });
  });

  group('terminal.read', () {
    test('observes output but cannot rewrite it', () async {
      final dir = writePlugin('reader', perms: ['terminal.read'], js: '''
plugin.on("terminal.output", function(ctx) {
  console.log("saw " + ctx.data);
  return "HACKED";
});
''');
      final bus = HookBus();
      final logs = <String>[];
      final svc = newEngine(bus, onLog: (id, lvl, m) => logs.add(m));
      await svc.loadPlugin(dir.path, grantedPermissions: {'terminal.read'});
      final out = bus.fireTransform(
          'terminal.output', TransformEvent(sessionId: 's', data: 'orig'));
      expect(out, 'orig');
      expect(logs, contains('saw orig'));
      svc.dispose();
    });
  });

  group('path containment', () {
    test('entry with ../ is rejected', () async {
      File('${tmpDir.path}/evil.js').writeAsStringSync('var pwned = 1;');
      final dir = writePlugin('trav', entry: '../evil.js');
      final svc = newEngine(HookBus());
      await expectLater(
          svc.loadPlugin(dir.path, grantedPermissions: {}), throwsException);
      svc.dispose();
    });

    test('absolute entry is rejected', () async {
      final evil = File('${tmpDir.path}/abs.js')..writeAsStringSync('1;');
      final dir = writePlugin('abs', entry: evil.path);
      final svc = newEngine(HookBus());
      await expectLater(
          svc.loadPlugin(dir.path, grantedPermissions: {}), throwsException);
      svc.dispose();
    });

    test('entry symlinked outside the plugin dir is rejected', () async {
      final outside = File('${tmpDir.path}/outside.js')
        ..writeAsStringSync('var x = 1;');
      final dir = writePlugin('sym', js: '');
      File('${dir.path}/index.js').deleteSync();
      Link('${dir.path}/index.js').createSync(outside.path);
      final svc = newEngine(HookBus());
      await expectLater(
          svc.loadPlugin(dir.path, grantedPermissions: {}), throwsException);
      svc.dispose();
    });

    test('resolvePluginFile accepts nested files, rejects escapes', () {
      final dir = writePlugin('ok');
      Directory('${dir.path}/panel').createSync();
      File('${dir.path}/panel/index.html').writeAsStringSync('<p/>');
      expect(resolvePluginFile(dir.path, 'panel/index.html'), isNotNull);
      expect(resolvePluginFile(dir.path, '../plugin.json'), isNull);
      expect(resolvePluginFile(dir.path, '/etc/passwd'), isNull);
      expect(resolvePluginFile(dir.path, 'panel/../../x'), isNull);
    });
  });

  group('consent binding', () {
    late List<String> consentIds;
    late List<String> errors;

    PluginLoader newLoader(ScriptEngineService svc) => PluginLoader(
          engine: svc,
          onConsentRequired: (id, m, d) => consentIds.add(id),
          onError: (id, msg) => errors.add('$id: $msg'),
        );

    setUp(() {
      consentIds = [];
      errors = [];
    });

    test('editing the entry JS after approval re-prompts', () async {
      final dir = writePlugin('edit', js: 'var a = 1;');
      final svc = newEngine(HookBus());
      final loader = newLoader(svc);
      await loader.approvePermissions(
          'sec.plugin', {'terminal.transform'}, dir.path);
      expect(svc.loadedManifests, hasLength(1));

      svc.unloadPlugin('sec.plugin');
      await loader.tryLoad(dir.path);
      expect(svc.loadedManifests, hasLength(1)); // unchanged -> silent load
      expect(consentIds, isEmpty);

      svc.unloadPlugin('sec.plugin');
      File('${dir.path}/index.js').writeAsStringSync('var a = 2;');
      await loader.tryLoad(dir.path);
      expect(consentIds, ['sec.plugin']);
      expect(svc.loadedManifests, isEmpty);
      svc.dispose();
    });

    test('panel file edits re-prompt', () async {
      final dir = writePlugin('panel', js: 'var a = 1;');
      Directory('${dir.path}/panel').createSync();
      File('${dir.path}/panel/index.html').writeAsStringSync('<p>a</p>');
      final svc = newEngine(HookBus());
      final loader = newLoader(svc);
      await loader.approvePermissions(
          'sec.plugin', {'terminal.transform'}, dir.path);
      svc.unloadPlugin('sec.plugin');
      File('${dir.path}/panel/index.html').writeAsStringSync('<p>b</p>');
      await loader.tryLoad(dir.path);
      expect(consentIds, ['sec.plugin']);
      svc.dispose();
    });

    test('stale grants are intersected with manifest permissions', () async {
      final dir = writePlugin('stale', js: 'var a = 1;');
      final svc = newEngine(HookBus());
      final loader = newLoader(svc);
      await loader.approvePermissions(
          'sec.plugin', {'terminal.transform', 'ssh.exec'}, dir.path);
      expect(svc.grantedPermissionsFor('sec.plugin'), {'terminal.transform'});
      svc.dispose();
    });

    test('stored grants beyond the current manifest do not survive', () async {
      final dir = writePlugin('stale2', js: 'var a = 1;');
      final svc = newEngine(HookBus());
      final loader = newLoader(svc);
      await loader.approvePermissions(
          'sec.plugin', {'terminal.transform'}, dir.path);
      svc.unloadPlugin('sec.plugin');
      // Simulate an old, broader grant for the same id and the same content.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('plugin::permissions::sec.plugin',
          ['terminal.transform', 'ssh.exec']);
      await loader.tryLoad(dir.path);
      expect(svc.grantedPermissionsFor('sec.plugin'), {'terminal.transform'});
      svc.dispose();
    });

    test('a dropped plugin reusing an approved id is prompted', () async {
      final dir = writePlugin('orig', js: 'var a = 1;');
      final svc = newEngine(HookBus());
      final loader = newLoader(svc);
      await loader.approvePermissions(
          'sec.plugin', {'terminal.transform'}, dir.path);
      svc.unloadPlugin('sec.plugin');
      final evil = writePlugin('evil', js: 'var evil = 1;');
      await loader.tryLoad(evil.path);
      expect(consentIds, ['sec.plugin']);
      expect(svc.loadedManifests, isEmpty);
      svc.dispose();
    });

    test('an entry escaping the plugin dir is reported, not loaded', () async {
      File('${tmpDir.path}/evil.js').writeAsStringSync('var x = 1;');
      final dir = writePlugin('esc', entry: '../evil.js', perms: []);
      final svc = newEngine(HookBus());
      final loader = newLoader(svc);
      await loader.tryLoad(dir.path);
      expect(svc.loadedManifests, isEmpty);
      expect(errors, isNotEmpty);
      svc.dispose();
    });
  });
}
