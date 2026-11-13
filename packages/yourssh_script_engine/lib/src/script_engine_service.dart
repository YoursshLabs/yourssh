import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'native/quickjs_runtime.dart';
import 'hook_bus.dart';
import 'plugin_manifest.dart';
import 'plugin_paths.dart';
import 'permission_guard.dart';
import 'plugin_error_tracker.dart';
import 'plugin_ui_registry.dart';
import 'bridge/storage_bridge.dart';
import 'bridge/ssh_bridge.dart';
import 'bridge/sftp_bridge.dart';
import 'bridge/ui_bridge.dart';
import 'bridge/terminal_inject_bridge.dart';

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

// JS prelude evaluated after the host bridges are registered and before the
// plugin entry. Defines the documented friendly globals (`ui`, `ssh`,
// `storage`) as thin wrappers over the raw `_x` host functions. A wrapper only
// forwards to a host function the PermissionGuard-gated bridge registered; when
// it is missing the call throws "Permission denied: <perm>", so no wrapper can
// reach a capability the plugin was not granted. Raw `_x` stays available.
const _kPrelude = r'''
(function(g) {
  function host(obj, fn, perm) {
    return function(arg) {
      if (typeof obj === 'undefined' || typeof obj[fn] !== 'function') {
        throw new Error('Permission denied: ' + perm + ' not granted');
      }
      var r = obj[fn](JSON.stringify(arg === undefined ? null : arg));
      return typeof r === 'string' ? JSON.parse(r) : null;
    };
  }
  var _u = typeof _ui === 'undefined' ? undefined : _ui;
  var _us = typeof _ui_statusbar === 'undefined' ? undefined : _ui_statusbar;
  var _s = typeof _ssh === 'undefined' ? undefined : _ssh;
  var _st = typeof _storage === 'undefined' ? undefined : _storage;
  var notify = host(_u, 'notify', 'ui.notify');
  var register = host(_u, 'registerPanel', 'ui.panel');
  var copy = host(_u, 'copyToClipboard', 'ui.clipboard');
  var addCommand = host(_u, 'addCommand', 'ui.statusbar or ui.panel');
  var sbAdd = host(_us, 'add', 'ui.statusbar');
  var sbUpdate = host(_us, 'update', 'ui.statusbar');
  var sbRemove = host(_us, 'remove', 'ui.statusbar');
  var sessions = host(_s, 'sessions', 'session.observe');
  var inject = host(_s, 'inject', 'terminal.inject');
  var sGet = host(_st, 'get', 'storage');
  var sSet = host(_st, 'set', 'storage');
  var sDel = host(_st, 'delete', 'storage');
  g.ui = {
    notify: function(message, options) {
      notify({message: String(message), type: (options && options.type) || 'info'});
    },
    statusbar: {
      add: function(id, o) {
        o = o || {};
        sbAdd({id: id, label: o.label, tooltip: o.tooltip});
      },
      update: function(id, o) {
        o = o || {};
        sbUpdate({id: id, label: o.label, tooltip: o.tooltip});
      },
      remove: function(id) { sbRemove({id: id}); }
    },
    panel: {
      register: function(c) {
        register({title: c.title, icon: c.icon, webviewEntry: c.webviewEntry});
        if (typeof c.onMessage === 'function') plugin._setPanelMessage(c.onMessage);
      }
    },
    clipboard: { copy: function(text) { copy({text: String(text)}); } },
    addCommand: function(c) {
      addCommand({id: c.id, label: c.label, keybinding: c.keybinding});
    }
  };
  g.ssh = {
    sessions: function() { return sessions(null) || []; },
    inject: function(sessionId, text) {
      inject({sessionId: sessionId, text: String(text)});
    }
  };
  g.storage = {
    get: function(key) { return sGet({key: key}); },
    set: function(key, value) { sSet({key: key, value: String(value)}); },
    delete: function(key) { sDel({key: key}); }
  };
})(this);
''';

class _LoadedPlugin {
  final String id;
  final PluginManifest manifest;
  final QuickJsRuntime runtime;
  final Set<String> granted;
  final PluginErrorTracker errorTracker;
  bool disabled = false;

  _LoadedPlugin(this.id, this.manifest, this.runtime, this.granted)
      : errorTracker = PluginErrorTracker(id);

  void dispose() => runtime.dispose();
}

class ScriptEngineService {
  final HookBus hookBus;
  final PluginUiRegistry? uiRegistry;
  final SshBridgeDelegate? sshDelegate;
  final SftpBridgeDelegate? sftpDelegate;
  final void Function(String pluginId, String level, String message)? onLog;

  /// Receives `ui.notify(message, {type})` calls from plugins holding the
  /// `ui.notify` permission. `type` is `info`, `warning` or `error`.
  final void Function(String pluginId, String message, String type)? onNotify;

  VoidCallback? onChange;

  List<PluginManifest> get loadedManifests =>
      _plugins.values.map((p) => p.manifest).toList();

  final _plugins = <String, _LoadedPlugin>{};

  /// Permissions the plugin was actually loaded with, or `null` if not loaded.
  Set<String>? grantedPermissionsFor(String pluginId) =>
      _plugins[pluginId] == null
          ? null
          : Set.unmodifiable(_plugins[pluginId]!.granted);

  ScriptEngineService({
    required this.hookBus,
    required this.uiRegistry,
    required this.sshDelegate,
    required this.sftpDelegate,
    this.onLog,
    this.onNotify,
  });

  Future<void> loadPlugin(
    String pluginDir, {
    required Set<String> grantedPermissions,
  }) async {
    final manifest = PluginManifest.fromJson(
        await File('$pluginDir/plugin.json').readAsString());

    // Only permissions the manifest still declares can be in force.
    final granted = grantedPermissions.intersection(manifest.permissions);

    final entryFile = resolvePluginFile(pluginDir, manifest.entry);
    if (entryFile == null) {
      throw ManifestException(
          'Entry "${manifest.entry}" is missing or outside the plugin directory');
    }

    final guard = PermissionGuard(pluginId: manifest.id, granted: granted);
    final rt = QuickJsRuntime();

    try {
      // Inject plugin bootstrap (plugin.on / plugin._dispatch / console)
      rt.eval(_kBootstrap, filename: '<bootstrap>', timeout: kLoadTimeout);

      // Register console bridge (always available — no permission required)
      _registerConsole(manifest.id, rt);

      // Register bridges based on permissions
      StorageBridge(manifest.id).register(rt);
      if (sshDelegate != null) {
        SshBridge(guard, sshDelegate!).register(rt);
        TerminalInjectBridge(guard, _TerminalInjectAdapter(sshDelegate!)).register(rt);
      }
      if (sftpDelegate != null) SftpBridge(guard, sftpDelegate!).register(rt);
      if (uiRegistry != null) {
        UiBridge(manifest.id, guard, uiRegistry!,
            onNotify == null ? null : (m, t) => onNotify!(manifest.id, m, t),
            (msg) async {
          final type = msg['type'] as String? ?? '';

          // Native operations bypass the JS bridges, so they must enforce the
          // same manifest permissions the bridges do — a panel is plugin-
          // controlled HTML and can post any message type.
          String denied(String permission) => json.encode({
                'type': 'error',
                'message': 'Permission denied: $permission not granted',
              });

          // Native SSH operations — handled by Dart, not JS (async-safe)
          if (type == 'ssh-exec') {
            if (!guard.has('ssh.exec')) return denied('ssh.exec');
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
            if (!guard.has('session.observe') && !guard.has('ssh.exec')) {
              return denied('session.observe');
            }
            final sessions = sshDelegate?.activeSessions() ?? [];
            return json.encode({'type': 'sessions', 'data': sessions});
          }

          // Native SFTP operations
          if (type == 'sftp-list') {
            if (!guard.has('sftp.read')) return denied('sftp.read');
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
            if (!guard.has('sftp.read')) return denied('sftp.read');
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
          final loaded = _plugins[manifest.id];
          if (loaded == null || loaded.disabled) {
            return json.encode(
                {'type': 'error', 'message': 'Plugin is disabled'});
          }
          try {
            final result = rt.callPanelMessage(msg);
            loaded.errorTracker.reset();
            return result;
          } catch (e) {
            _recordFailure(manifest.id, 'panel message', e);
            return json.encode({'type': 'error', 'message': e.toString()});
          }
        }).register(rt);
      }

      // Documented friendly globals (ui / ssh / storage) over the raw bridges.
      rt.eval(_kPrelude, filename: '<prelude>', timeout: kLoadTimeout);

      // Execute plugin entry point
      final src = await entryFile.readAsString();
      rt.eval(src, filename: manifest.entry, timeout: kLoadTimeout);

      // Wire JS dispatch into HookBus
      _wireHooks(manifest.id, rt, granted);

      _plugins[manifest.id] = _LoadedPlugin(manifest.id, manifest, rt, granted);
      onChange?.call();
    } catch (e) {
      rt.dispose();
      rethrow;
    }
  }

  void _wireHooks(
      String pluginId, QuickJsRuntime rt, Set<String> perms) {
    // terminal.output: terminal.transform may rewrite the data; terminal.read
    // only observes it (the hook runs but its return value is discarded).
    if (perms.contains('terminal.transform')) {
      hookBus.register('terminal.output', pluginId, (e) {
        return _dispatch(rt, 'terminal.output', e, pluginId);
      });
    } else if (perms.contains('terminal.read')) {
      hookBus.register('terminal.output', pluginId, (e) {
        _dispatch(rt, 'terminal.output', e, pluginId);
        return null;
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
    final loaded = _plugins[pluginId];
    if (loaded == null || loaded.disabled) return null;
    try {
      final resultJson =
          rt.callDispatch(event, {'sessionId': e.sessionId, 'data': e.data});
      loaded.errorTracker.reset();
      if (resultJson == null) return null;
      final decoded = json.decode(resultJson) as Map<String, dynamic>;
      if (decoded['cancelled'] == true) return false;
      return decoded['data'];
    } catch (err) {
      _recordFailure(pluginId, event, err);
      return null; // pass-through
    }
  }

  void _dispatchObserve(
      QuickJsRuntime rt, String event, ObserveEvent e, String pluginId) {
    final loaded = _plugins[pluginId];
    if (loaded == null || loaded.disabled) return;
    try {
      rt.callDispatch(event, {'sessionId': e.sessionId, ...e.payload});
      loaded.errorTracker.reset();
    } catch (err) {
      _recordFailure(pluginId, event, err);
    }
  }

  /// Counts a hook failure; once the circuit breaker trips the plugin stops
  /// receiving events and is unloaded (deferred, since hooks run while the
  /// HookBus is iterating its handler list).
  void _recordFailure(String pluginId, String where, Object err) {
    final loaded = _plugins[pluginId];
    if (loaded == null || loaded.disabled) return;
    loaded.errorTracker.recordError(
        weight: err is QuickJsTimeoutException
            ? PluginErrorTracker.timeoutWeight
            : 1);
    onLog?.call(pluginId, 'error', 'Error in $where: $err');
    if (loaded.errorTracker.isDisabled) {
      loaded.disabled = true;
      onLog?.call(pluginId, 'error',
          'Plugin disabled after repeated errors or timeouts');
      scheduleMicrotask(() {
        if (identical(_plugins[pluginId], loaded)) unloadPlugin(pluginId);
      });
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
