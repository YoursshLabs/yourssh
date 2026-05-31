import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/script_engine_service.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';
import 'package:yourssh_script_engine/src/bridge/ssh_bridge.dart';
import 'package:yourssh_script_engine/src/plugin_ui_registry.dart';

class _MockSshDelegate implements SshBridgeDelegate {
  @override
  List<Map<String, dynamic>> activeSessions() => [
    {'sessionId': 'mock-1', 'host': 'test.host', 'username': 'user', 'port': 22, 'connected': true}
  ];

  @override
  Future<Map<String, dynamic>> execCommand(String sessionId, String command) async =>
      {'stdout': 'mock output', 'stderr': '', 'exitCode': 0};

  @override
  void sendInput(String sessionId, String text) {}
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('plugin_engine_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('plugin transforms terminal.output via JS hook', () async {
    final pluginDir = Directory('${tmpDir.path}/test-plugin')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "test.plugin",
  "name": "Test",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.transform"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
plugin.on("terminal.output", function(ctx) {
  return ctx.data.replace("hello", "HELLO");
});
''');

    final bus = HookBus();
    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: null,
      sshDelegate: null,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'terminal.transform'});

    final result = bus.fireTransform(
        'terminal.output', TransformEvent(sessionId: 's1', data: 'say hello world'));

    expect(result, 'say HELLO world');
    svc.dispose();
  });

  test('plugin can cancel terminal.input via return false', () async {
    final pluginDir = Directory('${tmpDir.path}/cancel-plugin')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "cancel.plugin",
  "name": "Cancel",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.intercept"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
plugin.on("terminal.input", function(ctx) {
  if (ctx.data.indexOf("danger") !== -1) return false;
  return ctx.data;
});
''');

    final bus = HookBus();
    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: null,
      sshDelegate: null,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'terminal.intercept'});

    final blocked = bus.fireInterceptable(
        'terminal.input', TransformEvent(sessionId: 's1', data: 'danger command'));
    expect(blocked, isNull); // cancelled

    final allowed = bus.fireInterceptable(
        'terminal.input', TransformEvent(sessionId: 's1', data: 'safe command'));
    expect(allowed, 'safe command');
    svc.dispose();
  });

  test('native ssh-sessions panel message returns session list', () async {
    final pluginDir = Directory('${tmpDir.path}/native-test')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "test.native",
  "name": "Native Test",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["ui.panel", "session.observe"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
_ui.registerPanel(JSON.stringify({title: "Test", icon: "test", webviewEntry: "panel/index.html"}));
plugin._setPanelMessage(function(msg) { return {type: "from-js", received: msg.type}; });
''');

    final bus = HookBus();
    final mockSsh = _MockSshDelegate();
    final registry = PluginUiRegistry();

    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: registry,
      sshDelegate: mockSsh,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'ui.panel', 'session.observe'});

    final panel = registry.panels.first;

    // Native message (ssh-sessions) should NOT go to JS
    final result1 = await panel.onMessage({'type': 'ssh-sessions'});
    expect(result1, isNotNull);
    final decoded1 = json.decode(result1!) as Map<String, dynamic>;
    expect(decoded1['type'], 'sessions');
    expect((decoded1['data'] as List).first['host'], 'test.host');

    // JS message (from-js handler) should still work
    final result2 = await panel.onMessage({'type': 'ping'});
    final decoded2 = json.decode(result2!) as Map<String, dynamic>;
    expect(decoded2['type'], 'from-js');

    svc.dispose();
  });

  test('native ssh-exec panel message returns exec-result', () async {
    final pluginDir = Directory('${tmpDir.path}/ssh-exec-test')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "test.sshexec",
  "name": "SSH Exec Test",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["ui.panel", "session.observe"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
_ui.registerPanel(JSON.stringify({title: "Test", icon: "test", webviewEntry: "panel/index.html"}));
plugin._setPanelMessage(function(msg) { return {type: "from-js"}; });
''');

    final bus = HookBus();
    final mockSsh = _MockSshDelegate();
    final registry = PluginUiRegistry();

    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: registry,
      sshDelegate: mockSsh,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'ui.panel', 'session.observe'});

    final panel = registry.panels.first;

    final result = await panel.onMessage({
      'type': 'ssh-exec',
      'sessionId': 'mock-1',
      'command': 'echo hello',
    });
    expect(result, isNotNull);
    final decoded = json.decode(result!) as Map<String, dynamic>;
    expect(decoded['type'], 'exec-result');
    expect(decoded['stdout'], 'mock output');
    expect(decoded['exitCode'], 0);

    svc.dispose();
  });

  test('native sftp-list returns error when sftpDelegate is null', () async {
    final pluginDir = Directory('${tmpDir.path}/sftp-null-test')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "test.sftpnull",
  "name": "SFTP Null Test",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["ui.panel", "session.observe"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
_ui.registerPanel(JSON.stringify({title: "Test", icon: "test", webviewEntry: "panel/index.html"}));
plugin._setPanelMessage(function(msg) { return {type: "from-js"}; });
''');

    final bus = HookBus();
    final registry = PluginUiRegistry();

    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: registry,
      sshDelegate: null,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'ui.panel', 'session.observe'});

    final panel = registry.panels.first;

    final result = await panel.onMessage({
      'type': 'sftp-list',
      'sessionId': 'mock-1',
      'path': '/tmp',
    });
    expect(result, isNotNull);
    final decoded = json.decode(result!) as Map<String, dynamic>;
    expect(decoded['type'], 'error');
    expect(decoded['message'], 'SFTP not available');

    svc.dispose();
  });

  test('unloadPlugin removes hooks', () async {
    final pluginDir = Directory('${tmpDir.path}/unload-plugin')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
{
  "id": "unload.plugin",
  "name": "Unload",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.transform"]
}
''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
plugin.on("terminal.output", function(ctx) { return "INTERCEPTED"; });
''');

    final bus = HookBus();
    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: null,
      sshDelegate: null,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'terminal.transform'});
    svc.unloadPlugin('unload.plugin');

    final result = bus.fireTransform(
        'terminal.output', TransformEvent(sessionId: 's1', data: 'original'));
    expect(result, 'original'); // hook removed
    svc.dispose();
  });
}
