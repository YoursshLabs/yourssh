import 'dart:convert';
import '../permission_guard.dart';
import '../plugin_ui_registry.dart';
import '../js_runtime_registrar.dart';

class UiBridge {
  final String _pluginId;
  final PermissionGuard _guard;
  final PluginUiRegistry _registry;
  final void Function(String msg, String type)? _onNotify;

  UiBridge(this._pluginId, this._guard, this._registry, this._onNotify);

  void register(JsRuntimeRegistrar rt) {
    if (_guard.has('ui.notify')) {
      rt.registerHostFn('_ui', 'notify', _notify);
    }
    if (_guard.has('ui.statusbar')) {
      rt.registerHostFn('_ui_statusbar', 'add', _statusAdd);
      rt.registerHostFn('_ui_statusbar', 'update', _statusUpdate);
      rt.registerHostFn('_ui_statusbar', 'remove', _statusRemove);
    }
    if (_guard.has('ui.panel')) {
      rt.registerHostFn('_ui', 'registerPanel', _registerPanel);
    }
  }

  String? _notify(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _onNotify?.call(arg['message'] as String, arg['type'] as String? ?? 'info');
    return null;
  }

  String? _statusAdd(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.addStatusBarItem(StatusBarItem(
      id: arg['id'] as String,
      pluginId: _pluginId,
      label: arg['label'] as String,
      tooltip: arg['tooltip'] as String?,
    ));
    return null;
  }

  String? _statusUpdate(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.updateStatusBarItem(
      arg['id'] as String,
      label: arg['label'] as String?,
      tooltip: arg['tooltip'] as String?,
    );
    return null;
  }

  String? _statusRemove(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.removeStatusBarItem(arg['id'] as String);
    return null;
  }

  String? _registerPanel(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.addPanel(PluginPanelEntry(
      pluginId: _pluginId,
      title: arg['title'] as String,
      icon: arg['icon'] as String? ?? 'extension',
      webviewEntry: arg['webviewEntry'] as String,
      onMessage: (_) async => null,
    ));
    return null;
  }
}
