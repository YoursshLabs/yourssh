# Plugin System

YourSSH supports two types of plugins that coexist at runtime.

## Type 1: Dart Plugins (compile-time)

Compiled into the app binary. Registered in `app/lib/plugins/plugin_registry.dart` (`kRegisteredPlugins`).

### Adding a Dart Plugin

1. Add the package to `app/pubspec.yaml` dependencies and `dependency_overrides` (if local).
2. Import and instantiate in `plugin_registry.dart`.

### YourSSHPlugin Interface (`yourssh_plugin_api`)

```dart
abstract class YourSSHPlugin {
  Widget buildUI(BuildContext context, YourSSHPluginContext ctx);
  Future<void> onActivate(YourSSHPluginContext ctx);
  Future<void> onDeactivate();
  int get minApiVersion;
}
```

`YourSSHPluginContext` exposes:

- `activeSessions` — list of active SSH session IDs
- `execCommand(sessionId, cmd)` — run a command on a session
- `savePreference(key, value)` / `getPreference(key)` — namespaced storage

### Bundled Dart Plugins

| Package | Features |
|---|---|
| `yourssh_devops` | Containers, Network Tools, Cloudflare Tunnel, MCP Server, Mail Catcher, S3 Browser |
| `yourssh_web_tools` | In-app HTTP browser over port-forwarded connection |
| `yourssh_snippets` | Command snippet library |

## Type 2: JS Script Plugins (runtime)

Loaded at runtime from `~/.yourssh/plugins/`. No app rebuild required.

### Architecture

```
App (Dart/Flutter)
  └── PluginLoader — scans ~/.yourssh/plugins/, hot-reloads on file change
        └── QuickJsRuntime (FFI) — isolated JS context per plugin
              ├── JsRuntimeRegistrar — registers bridge APIs
              ├── HookBus — typed event routing
              └── PermissionGuard — enforces manifest permissions
```

### HookBus Event Types

| Hook type | Behavior |
|---|---|
| `transform` | Handler can modify the data (e.g., rewrite terminal output) |
| `intercept` | Handler can block the event entirely |
| `observe` | Side-effect only; cannot modify data |

### Events

| Event | Fires when |
|---|---|
| `terminal.output` | Data arrives from the SSH server |
| `terminal.input` | User types in the terminal |
| `session.connect` | Session is fully established |
| `session.disconnect` | Session closes |

### Bridges (Dart APIs callable from JS)

| Bridge | Available calls |
|---|---|
| `ssh` | `ssh.exec(sessionId, cmd)`, `ssh.write(sessionId, data)` |
| `sftp` | `sftp.list(sessionId, path)`, `sftp.readFile`, `sftp.writeFile` |
| `storage` | `storage.get(key)`, `storage.set(key, value)`, `storage.delete(key)` |
| `ui` | `ui.showNotification(msg)`, `ui.register(id, spec)` |

### Error Handling

`PluginErrorTracker` counts consecutive errors per plugin. If the threshold is exceeded, the plugin is automatically disabled. The user sees the error in the Plugin Console.

## Related Pages

- [Plugin Authoring](Developer-Guide-Plugin-Authoring) — write your first JS plugin
- [Architecture](Developer-Guide-Architecture) — where plugin loading fits in the app
