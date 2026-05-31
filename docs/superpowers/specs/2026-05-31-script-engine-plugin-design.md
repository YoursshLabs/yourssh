# Script Engine Plugin System — Design Spec

**Date:** 2026-05-31  
**Status:** Approved  
**Scope:** Dynamic plugin system using QuickJS (JavaScript) engine embedded via `dart:ffi`

---

## Goal

Allow third-party and power-user plugins to be installed and used without rebuilding the app. Plugins can observe, transform, intercept, and inject UI into the app — loaded from `~/.yourssh/plugins/` at runtime.

---

## 1. Architecture

### Plugin directory layout

```
~/.yourssh/plugins/
  log-highlighter/
    plugin.json     ← manifest
    index.js        ← entry point
    lib/helpers.js  ← optional additional files
  auto-commands/
    plugin.json
    index.js
```

### Manifest (`plugin.json`)

```json
{
  "id": "dev.yourssh.log-highlighter",
  "name": "Log Highlighter",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": [
    "terminal.transform",
    "session.observe"
  ]
}
```

### App-side components

| Component | Responsibility |
|-----------|---------------|
| `ScriptEngineService` | Owns all QuickJS instances; coordinates load/unload/reload |
| `PluginLoader` | Scans `~/.yourssh/plugins/`, validates manifests, triggers consent UI |
| `HookBus` | Central event bus; plugins register handlers, app fires events |
| `PermissionGuard` | Checks granted permissions before each bridge API call |
| `PluginUiRegistry` | Tracks UI contributions (status bar items, commands, context menu, panels) |

**Isolation principle:** Each plugin runs in its own QuickJS instance. A plugin crash cannot affect other plugins or the host app. Plugins share no memory.

---

## 2. Hook System

### Event catalog

| Event | Trigger | Sync/Async | Plugin can |
|-------|---------|------------|------------|
| `terminal.output` | SSH data → terminal | **sync** | transform data, pass-through |
| `terminal.input` | User keypress → SSH | **sync** | transform data, cancel (`false`) |
| `session.connect` | After connect succeeds | async | observe |
| `session.connect.before` | Before connect attempt | async | cancel (`false`) |
| `session.disconnect` | Session closes | async | observe |
| `command.before` | Before `ssh.exec()` | async | modify command, cancel |
| `command.after` | After `ssh.exec()` | async | observe result |
| `sftp.upload.before` | Before upload starts | async | cancel |
| `sftp.upload.after` | Upload complete | async | observe |
| `sftp.download.before` | Before download starts | async | cancel |
| `sftp.download.after` | Download complete | async | observe |

### Transform hook chain (`terminal.output`, `terminal.input`)

```
SshService: shell.stdout receives data
  │
  ▼
HookBus.fireTransform('terminal.output', { sessionId, data })
  ├── Plugin A handler → returns modified string
  ├── Plugin B handler → returns null (pass-through, keeps previous value)
  └── Plugin C handler → returns modified string
  │
  ▼
session.terminal.write(finalData)   ← called once with final result
```

Handler exceptions are caught silently; the previous data value is used. Plugin execution order is alphabetical by folder name.

### Interceptable hook chain

```
HookBus.fireInterceptable('terminal.input', { sessionId, data })
  ├── Plugin A → returns modified data        ✓ continue
  ├── Plugin B → returns false                ✗ STOP — event cancelled
  └── Plugin C                                ← never called
```

### Plugin JS API for hooks

```js
// Observe (read-only)
plugin.on('session.connect', (ctx) => {
  console.log('Connected to:', ctx.host);
});

// Transform
plugin.on('terminal.output', (ctx) => {
  return ctx.data.replace(/\bERROR\b/g, '\x1b[31mERROR\x1b[0m');
  // return null  ← pass-through
});

// Intercept / cancel
plugin.on('terminal.input', (ctx) => {
  if (ctx.data.includes('rm -rf /')) return false;
  return ctx.data;
});

// Async hook (non-hot-path only)
plugin.on('command.before', async (ctx) => {
  await ssh.exec(ctx.sessionId, 'logger "command run"');
  return ctx.command;
});
```

**Async is only permitted** on hooks not in the terminal hot path. `terminal.output` and `terminal.input` handlers must be synchronous.

---

## 3. Bridge API & Permissions

### Permission list

| Permission | Grants access to |
|-----------|-----------------|
| `terminal.read` | Observe `terminal.output`, `terminal.input` — handler return value is **ignored** (pass-through enforced) |
| `terminal.transform` | Modify `terminal.output` / `terminal.input` — handler return value replaces data |
| `terminal.intercept` | Cancel `terminal.input` events |
| `session.observe` | `session.connect`, `session.disconnect` events |
| `session.control` | `session.connect.before` — can cancel connect |
| `ssh.exec` | Call `ssh.exec()` bridge function |
| `sftp.read` | `sftp.list()`, `sftp.read()` |
| `sftp.write` | `sftp.write()`, `sftp.delete()`, `sftp.mkdir()` |
| `command.intercept` | `command.before` — modify or cancel exec commands |
| `ui.notify` | `ui.notify()` desktop notifications |
| `ui.statusbar` | Add/update/remove status bar items |
| `ui.panel` | Register a sidebar panel with WebView UI |

Permissions are stored in `SharedPreferences` under `plugin::<id>::permissions` after user approval. Revoking a permission triggers an immediate unload + reload of the plugin with the reduced API surface.

### Bridge API reference

```js
// SSH — requires: ssh.exec
ssh.exec(sessionId, command) → Promise<{ stdout, stderr, exitCode }>

// Sessions — requires: session.observe
ssh.sessions() → [{ sessionId, host, username, port, connected }]

// SFTP — requires: sftp.read
sftp.list(sessionId, remotePath) → Promise<[{ name, isDir, size, modified }]>
sftp.read(sessionId, remotePath) → Promise<string>

// SFTP — requires: sftp.write
sftp.write(sessionId, remotePath, content) → Promise<void>
sftp.delete(sessionId, remotePath)         → Promise<void>
sftp.mkdir(sessionId, remotePath)          → Promise<void>

// Storage — always available, auto-namespaced by plugin id
storage.get(key)         → Promise<string | null>
storage.set(key, value)  → Promise<void>
storage.delete(key)      → Promise<void>

// UI — requires: ui.notify
ui.notify(message, { type: 'info' | 'warning' | 'error' })

// UI — requires: ui.statusbar
ui.statusbar.add(id, { label, tooltip, onClick })
ui.statusbar.update(id, { label })
ui.statusbar.remove(id)

// UI — requires: ui.panel
ui.panel.register({ title, icon, webviewEntry, onMessage })

// Commands — requires: ui.panel or ui.statusbar
ui.commands.register(commandId, { label, keybinding?, handler })

// Context menu — requires: ui.panel or ui.statusbar
ui.contextMenu.add(id, { label, when, handler })

// Logging — always available
console.log(...args)
console.error(...args)
```

### PermissionGuard flow

```
Plugin calls ssh.exec(...)
  │
  ▼
Dart bridge receives call
  │
  ▼
PermissionGuard.check(pluginId, 'ssh.exec')
  ├── granted → forward to SshService.exec()
  └── denied  → throw PermissionDeniedError into JS runtime
```

---

## 4. UI Extension Points

Plugins cannot instantiate Flutter widgets directly. Two layers handle UI:

### Layer 1: Native extension points (declarative)

Flutter renders natively; plugin supplies data and callbacks.

**Status bar:**
```js
ui.statusbar.add('cpu-monitor', {
  label: 'CPU: --',
  tooltip: 'Remote CPU usage',
  onClick: () => ui.notify('Fetching...', { type: 'info' }),
});
```

**Command palette:**
```js
ui.commands.register('my-plugin.clear-logs', {
  label: 'Clear remote logs',
  keybinding: 'Ctrl+Shift+L',
  handler: async () => {
    const [s] = ssh.sessions();
    await ssh.exec(s.sessionId, 'truncate -s 0 /var/log/app.log');
  },
});
```

**Terminal context menu:**
```js
ui.contextMenu.add('my-plugin.copy-path', {
  label: 'Copy as SSH path',
  when: 'terminal.hasSelection',
  handler: (ctx) => { /* ctx.selection */ },
});
```

### Layer 2: Plugin panel (WebView)

For complex UI, plugins register a sidebar panel backed by an HTML/JS bundle. The panel WebView communicates with the plugin's QuickJS context via an internal JSON-RPC bridge:

```
Sidebar Panel (WebView)
  │  postMessage ↕ JSON-RPC
Plugin QuickJS runtime
  │  bridge API ↕
Dart / SshService
```

```js
ui.panel.register({
  title: 'Server Monitor',
  icon: 'monitor',
  webviewEntry: 'panel/index.html',
  onMessage: async (msg) => {
    if (msg.type === 'fetch-stats') {
      const r = await ssh.exec(msg.sessionId, 'df -h');
      return { type: 'stats', data: r.stdout };
    }
  },
});
```

### PluginUiRegistry

`PluginUiRegistry` is a `ChangeNotifier`. Flutter widgets that render status bar items, command palette, and context menus subscribe to it and rebuild automatically when plugins add or remove contributions.

---

## 5. Plugin Lifecycle

### Load sequence (app start)

```
App start
  │
  ▼
PluginLoader.scan(~/.yourssh/plugins/)
  ├── validate plugin.json (id, version, entry file exists)
  ├── check minAppVersion compatibility
  ├── load saved permissions from SharedPreferences
  │     ├── new or changed permissions → show consent dialog
  │     └── already approved → proceed
  │
  ▼
ScriptEngineService.load(plugin)
  ├── create new isolated QuickJS instance
  ├── inject bridge API (only functions plugin has permission for)
  ├── execute index.js
  └── plugin.on(...) calls → register handlers in HookBus
```

### Hot-reload (developer workflow)

A file watcher monitors `~/.yourssh/plugins/`. On any `.js` change:

```
ScriptEngineService.reload(pluginId)
  ├── HookBus.unregisterAll(pluginId)
  ├── PluginUiRegistry.clear(pluginId)
  ├── destroy old QuickJS instance
  ├── create new QuickJS instance
  └── execute index.js
```

No app restart needed.

### Error handling — circuit breaker

| Error count | Action |
|------------|--------|
| < 5 | Log to Plugin Console, use pass-through for that call |
| = 5 | Warn user: "Plugin X is encountering repeated errors" |
| = 10 | Auto-disable plugin, notify user |

### Hook timeouts

| Hook | Timeout | Reason |
|------|---------|--------|
| `terminal.output`, `terminal.input` | 5ms (sync) | Hot path — must not lag terminal |
| `command.before`, `sftp.*` | 3000ms | User-facing operations |
| `session.connect` observe | 1000ms | Background event |

### Marketplace install flow

```
User triggers install (URL / registry lookup)
  │
  ▼
Download to ~/.yourssh/plugins/.staging/<id>/
  │
  ▼
Validate manifest + static JS scan (detect obvious malicious patterns)
  │
  ▼
Show consent dialog with permission list
  ├── user selects which permissions to grant
  └── user clicks Allow
  │
  ▼
Move .staging/<id>/ → plugins/<id>/
ScriptEngineService.load(plugin)
```

### Uninstall vs disable

- **Disable:** unload QuickJS instance, clear HookBus + UiRegistry, keep folder on disk
- **Uninstall:** disable + delete plugin folder + remove `plugin::<id>::*` keys from SharedPreferences

---

## 6. Implementation Notes

- **QuickJS binding:** Use `quickjs_dart` or author thin FFI bindings against the upstream quickjs C source. Build for macOS (arm64 + x86_64 universal), Windows (x64), Linux (x64).
- **Async bridge:** Dart `Completer` per pending JS Promise; QuickJS poll loop runs on a background isolate to avoid blocking the Flutter UI thread.
- **Storage namespace:** `plugin::<id>::storage::<key>` in SharedPreferences — distinct from permission keys (`plugin::<id>::permissions`).
- **Plugin Console:** A debug panel in Settings → Plugins showing `console.log` / `console.error` output per plugin, plus error count and circuit breaker state.
- **Static scan on install:** Regex-based heuristic only (e.g., detect `eval(atob(...))`, known exfiltration patterns). Not a security guarantee — the consent dialog is the primary trust mechanism.
