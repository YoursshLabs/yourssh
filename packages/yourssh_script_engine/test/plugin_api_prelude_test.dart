import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_script_engine/src/bridge/ssh_bridge.dart';
import 'package:yourssh_script_engine/src/bridge/storage_bridge.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';
import 'package:yourssh_script_engine/src/plugin_ui_registry.dart';
import 'package:yourssh_script_engine/src/script_engine_service.dart';

class _FakeSsh implements SshBridgeDelegate {
  final inputs = <String>[];
  @override
  List<Map<String, dynamic>> activeSessions() => [
        {'sessionId': 's1', 'host': 'h', 'username': 'u', 'port': 22, 'connected': true}
      ];
  @override
  Future<Map<String, dynamic>> execCommand(String s, String c) async =>
      {'stdout': '', 'stderr': '', 'exitCode': 0};
  @override
  void sendInput(String sessionId, String text) => inputs.add('$sessionId:$text');
}

void main() {
  late Directory tmp;
  late PluginUiRegistry registry;
  late _FakeSsh ssh;
  late List<String> notes;
  late List<String> logs;
  late ScriptEngineService svc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await StorageBridge.warmup();
    tmp = Directory.systemTemp.createTempSync('plugin_prelude_');
    registry = PluginUiRegistry();
    ssh = _FakeSsh();
    notes = [];
    logs = [];
    svc = ScriptEngineService(
      hookBus: HookBus(),
      uiRegistry: registry,
      sshDelegate: ssh,
      sftpDelegate: null,
      onLog: (id, level, msg) => logs.add('$level:$msg'),
      onNotify: (id, msg, type) => notes.add('$type:$msg'),
    );
  });

  tearDown(() {
    svc.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> load(String js, Set<String> perms) async {
    final dir = Directory('${tmp.path}/p')..createSync();
    File('${dir.path}/plugin.json').writeAsStringSync(json.encode({
      'id': 'test.prelude',
      'name': 'P',
      'version': '1.0.0',
      'entry': 'index.js',
      'minAppVersion': '1.0.0',
      'permissions': perms.toList(),
    }));
    File('${dir.path}/index.js').writeAsStringSync(js);
    await svc.loadPlugin(dir.path, grantedPermissions: perms);
  }

  test('ui.panel.register registers a panel and routes onMessage', () async {
    await load('''
ui.panel.register({title: "T", icon: "note", webviewEntry: "panel/index.html",
  onMessage: function(m) { return {type: "echo", got: m.type}; }});
''', {'ui.panel'});
    expect(registry.panels.single.title, 'T');
    final r = await registry.panels.single.onMessage({'type': 'ping'});
    expect(json.decode(r!)['got'], 'ping');
  });

  test('storage.set/get/delete round trip', () async {
    await load('''
storage.set("k", "v");
var a = storage.get("k");
console.log("a=" + (a && a.value));
storage.delete("k");
console.log("b=" + storage.get("k"));
''', {});
    expect(logs, ['log:a=v', 'log:b=null']);
  });

  test('ui.notify reaches the host callback', () async {
    await load('ui.notify("hi", {type: "warning"}); ui.notify("yo");',
        {'ui.notify'});
    expect(notes, ['warning:hi', 'info:yo']);
  });

  test('ui.statusbar add/update/remove, clipboard and addCommand', () async {
    await load('''
ui.statusbar.add("a", {label: "L", tooltip: "t"});
ui.statusbar.update("a", {label: "L2"});
ui.statusbar.add("b", {label: "B"});
ui.statusbar.remove("b");
ui.addCommand({id: "c", label: "Cmd"});
''', {'ui.statusbar'});
    expect(registry.statusBarItems.map((i) => i.label), ['L2']);
    expect(registry.commands.single.label, 'Cmd');
  });

  test('ssh.sessions and ssh.inject use the delegate', () async {
    await load('''
var s = ssh.sessions();
console.log("n=" + s.length + " " + s[0].sessionId);
ssh.inject("s1", "ls\\n");
''', {'session.observe', 'terminal.inject'});
    expect(logs, ['log:n=1 s1']);
    expect(ssh.inputs, ['s1:ls\n']);
  });

  test('wrappers do not bypass permissions', () async {
    await load('''
try { ui.panel.register({title: "x", webviewEntry: "p"}); console.log("allowed"); }
catch (e) { console.log("denied:" + e.message); }
try { ssh.inject("s1", "x"); console.log("allowed"); }
catch (e) { console.log("denied:" + e.message); }
''', {'ui.notify'});
    expect(logs.length, 2);
    expect(logs.every((l) => l.startsWith('log:denied:')), isTrue);
    expect(logs[0], contains('ui.panel'));
    expect(logs[1], contains('terminal.inject'));
    expect(registry.panels, isEmpty);
    expect(ssh.inputs, isEmpty);
  });

  test('plugin using only raw _x API still loads', () async {
    await load('''
_ui.registerPanel(JSON.stringify({title: "Raw", icon: "x", webviewEntry: "p"}));
_storage.set(JSON.stringify({key: "k", value: "v"}));
''', {'ui.panel'});
    expect(registry.panels.single.title, 'Raw');
  });
}
