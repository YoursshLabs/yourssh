import 'dart:convert';
import 'package:flutter/services.dart';
import '../permission_guard.dart';
import '../plugin_ui_registry.dart';
import '../js_runtime_registrar.dart';

class UiBridge {
  final String _pluginId;
  final PermissionGuard _guard;
  final PluginUiRegistry _registry;
  final void Function(String msg, String type)? _onNotify;
  final Future<String?> Function(Map<String, dynamic>)? _onPanelMessage;

  UiBridge(this._pluginId, this._guard, this._registry, this._onNotify,
      [this._onPanelMessage]);

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
    if (_guard.has('ui.clipboard')) {
      rt.registerHostFn('_ui', 'copyToClipboard', _clipboardCopy);
    }
    if (_guard.has('ui.statusbar') || _guard.has('ui.panel')) {
      // Commands registration available when plugin has any UI permission.
      // NOTE: The handler is a no-op stub — invoking JS callbacks from Dart
      // synchronously is not supported yet. The command will appear in the
      // palette but clicking it won't call back into JS. An async callback
      // bridge is required for full JS handler support (tracked as TODO).
      rt.registerHostFn('_ui', 'addCommand', _addCommand);
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

  String? _clipboardCopy(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final text = arg['text'] as String;
    Clipboard.setData(ClipboardData(text: text));
    return null;
  }

  String? _registerPanel(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.addPanel(PluginPanelEntry(
      pluginId: _pluginId,
      title: arg['title'] as String,
      icon: arg['icon'] as String? ?? 'extension',
      webviewEntry: arg['webviewEntry'] as String,
      onMessage: _onPanelMessage ?? (_) async => null,
    ));
    return null;
  }

  String? _addCommand(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final commandId = '$_pluginId.${arg['id'] as String}';
    _registry.addCommand(CommandEntry(
      commandId: commandId,
      pluginId: _pluginId,
      label: arg['label'] as String,
      keybinding: arg['keybinding'] as String?,
      // Handler is a no-op stub. Invoking JS callbacks from Dart synchronously
      // is not currently supported. The command appears in the palette but
      // clicking it does not invoke JS. TODO: wire to JS callback via async eval.
      handler: () {},
    ));
    return null;
  }
}
