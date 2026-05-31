import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/bridge/ui_bridge.dart';
import 'package:yourssh_script_engine/src/permission_guard.dart';
import 'package:yourssh_script_engine/src/plugin_ui_registry.dart';

// Minimal JsRuntimeRegistrar for testing
class _MockRuntime implements JsRuntimeRegistrar {
  final _fns = <String, Map<String, String? Function(String)>>{};

  @override
  void registerHostFn(String bridgeName, String fnName,
      String? Function(String arg) handler) {
    _fns.putIfAbsent(bridgeName, () => {})[fnName] = handler;
  }

  String? call(String bridge, String fn, String arg) =>
      _fns[bridge]?[fn]?.call(arg);
}

void main() {
  test('registers statusbar functions when ui.statusbar permission granted',
      () {
    final reg = PluginUiRegistry();
    final guard = PermissionGuard(pluginId: 'p1', granted: {'ui.statusbar'});
    final rt = _MockRuntime();
    UiBridge('p1', guard, reg, null).register(rt);
    expect(rt._fns['_ui_statusbar']?.containsKey('add'), true);
    expect(rt._fns['_ui_statusbar']?.containsKey('update'), true);
    expect(rt._fns['_ui_statusbar']?.containsKey('remove'), true);
  });

  test('does not register statusbar functions without permission', () {
    final reg = PluginUiRegistry();
    final guard = PermissionGuard(pluginId: 'p1', granted: {});
    final rt = _MockRuntime();
    UiBridge('p1', guard, reg, null).register(rt);
    expect(rt._fns.containsKey('_ui_statusbar'), false);
  });

  test('statusbar add updates registry', () {
    final reg = PluginUiRegistry();
    final guard = PermissionGuard(pluginId: 'p1', granted: {'ui.statusbar'});
    final rt = _MockRuntime();
    UiBridge('p1', guard, reg, null).register(rt);
    rt.call('_ui_statusbar', 'add',
        '{"id":"s1","label":"Test","tooltip":"tip"}');
    expect(reg.statusBarItems.length, 1);
    expect(reg.statusBarItems.first.label, 'Test');
  });

  test('notify callback is invoked', () {
    final reg = PluginUiRegistry();
    final guard = PermissionGuard(pluginId: 'p1', granted: {'ui.notify'});
    final rt = _MockRuntime();
    String? gotMsg;
    UiBridge('p1', guard, reg, (msg, type) => gotMsg = msg).register(rt);
    rt.call('_ui', 'notify', '{"message":"hello","type":"info"}');
    expect(gotMsg, 'hello');
  });
}
