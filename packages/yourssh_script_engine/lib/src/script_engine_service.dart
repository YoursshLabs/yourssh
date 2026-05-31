import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'native/quickjs_runtime.dart';
import 'hook_bus.dart';
import 'plugin_manifest.dart';
import 'permission_guard.dart';
import 'plugin_error_tracker.dart';
import 'plugin_ui_registry.dart';
import 'bridge/storage_bridge.dart';
import 'bridge/ssh_bridge.dart';
import 'bridge/sftp_bridge.dart';
import 'bridge/ui_bridge.dart';
import 'bridge/terminal_inject_bridge.dart';
import 'bridge/migration_bridge.dart';

// JS bootstrap injected at runtime load time.
// Provides `plugin.on(event, handler)`, `plugin._dispatch(event, ctxJson)`,
// `plugin._setPanelMessage(handler)`, `plugin._invokePanelMessage(msgJson)`,
// and `console.log/warn/error` backed by the _console host bridge.
const _kBootstrap = r'''
var plugin = (function() {
  var _h = {};
  var _panelMessageHandler = null;
  return {
    on: function(event, handler) {
      if (!_h[event]) _h[event] = [];
      _h[event].push(handler);
    },
    _dispatch: function(event, ctxJson) {
      var ctx = JSON.parse(ctxJson);
      var handlers = _h[event] || [];
      var current = ctx;
      for (var i = 0; i < handlers.length; i++) {
        var r = handlers[i](current);
        if (r === false) return {cancelled: true};
        if (typeof r === 'string') current = Object.assign({}, current, {data: r});
      }
      return {data: current.data};
    },
    _setPanelMessage: function(handler) {
      _panelMessageHandler = handler;
    },
    _invokePanelMessage: function(msgJson) {
      if (!_panelMessageHandler) return null;
      try {
        var msg = JSON.parse(msgJson);
        var result = _panelMessageHandler(msg);
        if (result === null || result === undefined) return null;
        return JSON.stringify(result);
      } catch(e) {
        return JSON.stringify({type: 'error', message: String(e)});
      }
    }
  };
})();

var console = {
  log: function() {
    var msg = Array.prototype.slice.call(arguments).join(' ');
    _console.log(JSON.stringify(msg));
  },
  warn: function() {
    var msg = Array.prototype.slice.call(arguments).join(' ');
    _console.warn(JSON.stringify(msg));
  },
  error: function() {
    var msg = Array.prototype.slice.call(arguments).join(' ');
    _console.error(JSON.stringify(msg));
  }
};
''';

class _LoadedPlugin {
  final String id;
  final PluginManifest manifest;
  final QuickJsRuntime runtime;
  final PluginErrorTracker errorTracker;

  _LoadedPlugin(this.id, this.manifest, this.runtime)
      : errorTracker = PluginErrorTracker(id);

  void dispose() => runtime.dispose();
}

class ScriptEngineService {
  final HookBus hookBus;
  final PluginUiRegistry? uiRegistry;
  final SshBridgeDelegate? sshDelegate;
  final SftpBridgeDelegate? sftpDelegate;
  final void Function(String pluginId, String level, String message)? onLog;

  VoidCallback? onChange;

  List<PluginManifest> get loadedManifests =>
      _plugins.values.map((p) => p.manifest).toList();

  final _plugins = <String, _LoadedPlugin>{};

  ScriptEngineService({
    required this.hookBus,
    required this.uiRegistry,
    required this.sshDelegate,
    required this.sftpDelegate,
    this.onLog,
  });

  Future<void> loadPlugin(
    String pluginDir, {
    required Set<String> grantedPermissions,
  }) async {
    final manifest = PluginManifest.fromJson(
        await File('$pluginDir/plugin.json').readAsString());

    final guard =
        PermissionGuard(pluginId: manifest.id, granted: grantedPermissions);
    final rt = QuickJsRuntime();

    try {
      // Inject plugin bootstrap (plugin.on / plugin._dispatch / console)
      rt.eval(_kBootstrap, filename: '<bootstrap>');

      // Register console bridge (always available — no permission required)
      _registerConsole(manifest.id, rt);

      // Register bridges based on permissions
      StorageBridge(manifest.id).register(rt);
      MigrationBridge().register(rt);
      if (sshDelegate != null) {
        SshBridge(guard, sshDelegate!).register(rt);
        TerminalInjectBridge(guard, _TerminalInjectAdapter(sshDelegate!)).register(rt);
      }
      if (sftpDelegate != null) SftpBridge(guard, sftpDelegate!).register(rt);
      if (uiRegistry != null) {
        UiBridge(manifest.id, guard, uiRegistry!, null, (msg) async {
          final type = msg['type'] as String? ?? '';

          // Native SSH operations — handled by Dart, not JS (async-safe)
          if (type == 'ssh-exec') {
            if (sshDelegate == null) {
              return json.encode({'type': 'error', 'message': 'SSH not available'});
            }
            try {
              final sessionId = msg['sessionId'] as String;
              final command = msg['command'] as String;
              final result = await sshDelegate!.execCommand(sessionId, command);
              result['type'] = 'exec-result';
              return json.encode(result);
            } catch (e) {
              return json.encode({'type': 'error', 'message': e.toString()});
            }
          }

          if (type == 'ssh-sessions') {
            final sessions = sshDelegate?.activeSessions() ?? [];
            return json.encode({'type': 'sessions', 'data': sessions});
          }

          // Native SFTP operations
          if (type == 'sftp-list') {
            if (sftpDelegate == null) {
              return json.encode({'type': 'error', 'message': 'SFTP not available'});
            }
            try {
              final sessionId = msg['sessionId'] as String;
              final path = msg['path'] as String;
              final entries = await sftpDelegate!.listDir(sessionId, path);
              return json.encode({'type': 'sftp-entries', 'data': entries});
            } catch (e) {
              return json.encode({'type': 'error', 'message': e.toString()});
            }
          }

          if (type == 'sftp-read') {
            if (sftpDelegate == null) {
              return json.encode({'type': 'error', 'message': 'SFTP not available'});
            }
            try {
              final sessionId = msg['sessionId'] as String;
              final path = msg['path'] as String;
              final content = await sftpDelegate!.readFile(sessionId, path);
              return json.encode({'type': 'sftp-content', 'content': content});
            } catch (e) {
              return json.encode({'type': 'error', 'message': e.toString()});
            }
          }

          // Default: route to JS plugin's panel message handler
          try {
            final result = rt.callPanelMessage(msg);
            return result;
          } catch (e) {
            return json.encode({'type': 'error', 'message': e.toString()});
          }
        }).register(rt);
      }

      // Execute plugin entry point
      final src = await File('$pluginDir/${manifest.entry}').readAsString();
      rt.eval(src, filename: manifest.entry);

      // Wire JS dispatch into HookBus
      _wireHooks(manifest.id, rt, grantedPermissions);

      _plugins[manifest.id] = _LoadedPlugin(manifest.id, manifest, rt);
      onChange?.call();
    } catch (e) {
      rt.dispose();
      rethrow;
    }
  }

  void _wireHooks(
      String pluginId, QuickJsRuntime rt, Set<String> perms) {
    // Transform hooks: terminal.output requires terminal.transform or terminal.read
    if (perms.contains('terminal.transform') || perms.contains('terminal.read')) {
      hookBus.register('terminal.output', pluginId, (e) {
        return _dispatch(rt, 'terminal.output', e, pluginId);
      });
    }

    // Interceptable hooks: terminal.input requires terminal.intercept
    if (perms.contains('terminal.intercept')) {
      hookBus.register('terminal.input', pluginId, (e) {
        return _dispatch(rt, 'terminal.input', e, pluginId);
      });
    }

    // Observe hooks
    if (perms.contains('session.observe') || perms.contains('session.control')) {
      hookBus.registerObserver('session.connect', pluginId, (e) {
        _dispatchObserve(rt, 'session.connect', e, pluginId);
      });
      hookBus.registerObserver('session.disconnect', pluginId, (e) {
        _dispatchObserve(rt, 'session.disconnect', e, pluginId);
      });
    }

    if (perms.contains('command.intercept')) {
      hookBus.register('command.before', pluginId, (e) {
        return _dispatch(rt, 'command.before', e, pluginId);
      });
      hookBus.registerObserver('command.after', pluginId, (e) {
        _dispatchObserve(rt, 'command.after', e, pluginId);
      });
    }

    if (perms.contains('session.control')) {
      hookBus.register('session.connect.before', pluginId, (e) {
        return _dispatch(rt, 'session.connect.before', e, pluginId);
      });
    }
  }

  dynamic _dispatch(
      QuickJsRuntime rt, String event, TransformEvent e, String pluginId) {
    try {
      final resultJson =
          rt.callDispatch(event, {'sessionId': e.sessionId, 'data': e.data});
      if (resultJson == null) return null;
      final decoded = json.decode(resultJson) as Map<String, dynamic>;
      if (decoded['cancelled'] == true) return false;
      return decoded['data'];
    } catch (err) {
      final loaded = _plugins[pluginId];
      loaded?.errorTracker.recordError();
      debugPrint('[ScriptEngine] $pluginId error in $event: $err');
      return null; // pass-through
    }
  }

  void _dispatchObserve(
      QuickJsRuntime rt, String event, ObserveEvent e, String pluginId) {
    try {
      rt.callDispatch(event, {'sessionId': e.sessionId, ...e.payload});
    } catch (err) {
      debugPrint('[ScriptEngine] $pluginId observer error in $event: $err');
    }
  }

  void _registerConsole(String pluginId, QuickJsRuntime rt) {
    for (final level in ['log', 'warn', 'error']) {
      final lvl = level; // capture loop variable
      rt.registerHostFn('_console', lvl, (arg) {
        final decoded = arg == 'null' ? '' : _safeDecodeArg(arg);
        onLog?.call(pluginId, lvl, decoded);
        return null;
      });
    }
  }

  String _safeDecodeArg(String arg) {
    try {
      final v = json.decode(arg);
      return v is String ? v : arg;
    } catch (_) {
      return arg;
    }
  }

  void unloadPlugin(String pluginId) {
    hookBus.unregisterAll(pluginId);
    uiRegistry?.clearPlugin(pluginId);
    _plugins[pluginId]?.dispose();
    _plugins.remove(pluginId);
    onChange?.call();
  }

  void dispose() {
    for (final p in _plugins.values) {
      p.dispose();
    }
    _plugins.clear();
  }
}

class _TerminalInjectAdapter implements TerminalInjectDelegate {
  final SshBridgeDelegate _ssh;
  _TerminalInjectAdapter(this._ssh);
  @override
  void sendInput(String sessionId, String text) => _ssh.sendInput(sessionId, text);
}
