# Snippets Plugin Migration to JS Script Engine — Design Spec

**Date:** 2026-05-31  
**Status:** Approved  
**Scope:** Replace compiled `yourssh_snippets` Dart plugin with a JS script engine plugin. Includes new bridge APIs, WebView panel renderer, data migration, and bundled plugin installer.

---

## Goal

Migrate the Snippets compiled plugin to the JS script engine so it loads from `~/.yourssh/plugins/snippets/` at runtime without rebuilding the app. Users see the same sidebar position and UX; the implementation is now hot-reloadable JS + WebView.

---

## 1. Architecture Overview

### New / changed files

```
app/assets/bundled_plugins/snippets/
  plugin.json           ← bundled manifest
  index.js              ← plugin logic + data migration
  panel/index.html      ← WebView UI

packages/yourssh_script_engine/
  lib/src/bridge/terminal_inject_bridge.dart  ← ssh.inject() bridge
  lib/src/bridge/ui_bridge.dart               ← add ui.clipboard.copy()
  lib/src/plugin_manifest.dart                ← add terminal.inject, ui.clipboard permissions

app/lib/
  services/ssh_service.dart               ← add sendInput(sessionId, text)
  plugins/plugin_registry.dart            ← remove YourSSHSnippetsPlugin
  utils/bundled_plugin_installer.dart     ← NEW: copy assets → ~/.yourssh/plugins/
  widgets/script_plugin_panel_screen.dart ← NEW: WebView renderer for plugin panels
  screens/main_screen.dart                ← wire panels into sidebar + content area
  main.dart                               ← call BundledPluginInstaller before scanAndLoad
```

### Startup flow

```
App start
  │
  ├── BundledPluginInstaller.ensureInstalled('snippets')
  │     └── Copy app assets → ~/.yourssh/plugins/snippets/ (skip if already exists)
  │
  ├── PluginLoader.scanAndLoad()
  │     └── Load snippets JS plugin → PluginUiRegistry.addPanel(...)
  │
  └── MainScreen sidebar
        └── Detect PluginUiRegistry.panels → render alongside compiled plugins
              └── User clicks "Snippets" → ScriptPluginPanelScreen (WebView)
```

---

## 2. New Bridge APIs

### `ssh.inject(sessionId, text)` — send text into terminal shell

**New permission:** `terminal.inject`

Dart: add `sendInput(String sessionId, String text)` to `SshService`:
```dart
void sendInput(String sessionId, String text) {
  final shell = _shells[sessionId];
  shell?.write(Uint8List.fromList(text.codeUnits));
}
```

Create `TerminalInjectBridge` in `lib/src/bridge/terminal_inject_bridge.dart` that registers `_ssh.inject` host function. Requires `terminal.inject` permission.

JS usage:
```js
await ssh.inject(sessionId, "ls -la\n");  // \n submits the command
```

Returns `Promise<void>`. Throws if session or shell not found.

### `ui.clipboard.copy(text)` — copy to system clipboard

**New permission:** `ui.clipboard`

Add to `UiBridge.register()`:
```dart
if (_guard.has('ui.clipboard')) {
  rt.registerHostFn('_ui', 'copyToClipboard', _copyToClipboard);
}
```

Dart calls `Clipboard.setData(ClipboardData(text: text))`. Returns synchronously (no Promise needed in JS).

JS usage:
```js
ui.clipboard.copy(snippet.command);
```

### `_migration.*` — one-time data migration (internal, not public API)

Two sync bridge functions registered in `ScriptEngineService.loadPlugin()` before the plugin entry JS is executed (alongside StorageBridge, SshBridge, etc.), unconditionally for all plugins:

| Function | Dart implementation |
|----------|-------------------|
| `_migration.readOldSnippets()` | `SharedPreferences.getString("yourssh.snippets")` → JSON string or null |
| `_migration.clearOldSnippets()` | `SharedPreferences.remove("yourssh.snippets")` |

These are prefixed with `_migration` to signal they are internal. They are only effective once — after `clearOldSnippets()` the key is gone and `readOldSnippets()` returns null.

### Permission list additions

Add to `_kKnownPermissions` in `plugin_manifest.dart`:
- `terminal.inject` — write text directly into an active shell
- `ui.clipboard` — write to system clipboard

---

## 3. Sidebar Integration

### `_MainScreenState` additions

```dart
String? _activeScriptPanel;  // pluginId of selected script panel
```

### Sidebar: render script panels after compiled plugins

In the plugins section of the sidebar, after the existing compiled plugin items:

```dart
Consumer<PluginUiRegistry>(
  builder: (context, registry, _) => Column(
    children: registry.panels.map((panel) =>
      _SidebarPluginItem(
        icon: Icons.extension,
        label: panel.title,
        isActive: _activeScriptPanel == panel.pluginId,
        onTap: () => setState(() {
          _nav = NavSection.plugins;
          _activeScriptPanel = panel.pluginId;
          _activePluginId = null;
        }),
      ),
    ).toList(),
  ),
)
```

### Content area: switch between compiled and script panels

```dart
// In the main content build:
if (_activeScriptPanel != null) {
  final panel = context.read<PluginUiRegistry>()
      .panels.firstWhere((p) => p.pluginId == _activeScriptPanel);
  return ScriptPluginPanelScreen(panel: panel);
} else if (_activePluginId != null) {
  // existing compiled plugin rendering
}
```

When `_activeScriptPanel` is set, `_activePluginId` is null, and vice versa. Selecting a compiled plugin clears `_activeScriptPanel`.

---

## 4. ScriptPluginPanelScreen

```dart
class ScriptPluginPanelScreen extends StatefulWidget {
  final PluginPanelEntry panel;
}
```

Uses `webview_flutter` (`WebViewController`):

1. Resolve plugin folder path: `${home}/.yourssh/plugins/${panel.pluginId}/`
2. Load `file://$pluginDir/${panel.webviewEntry}` via `controller.loadFile(path)`
3. Register JavaScript channel `pluginBridge` for WebView → Dart messages
4. On message received: call `panel.onMessage(decoded)` → get result → `controller.runJavaScript("window.pluginBridge.receive(${json.encode(result)})")`

**Communication protocol:**

```
WebView sends:    { id: "req-1", type: "get-snippets" }
Dart calls:       panel.onMessage({ type: "get-snippets" })  →  plugin JS  →  { type: "snippets", data: [...] }
WebView receives: window.pluginBridge.receive({ id: "req-1", type: "snippets", data: [...] })
```

The `id` field correlates requests to responses so the WebView can resolve the correct Promise.

---

## 5. Snippets JS Plugin

### `plugin.json`

```json
{
  "id": "dev.yourssh.snippets",
  "name": "Snippets",
  "version": "2.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": [
    "session.observe",
    "terminal.inject",
    "ui.clipboard",
    "ui.panel"
  ]
}
```

### `index.js`

Responsibilities:
1. **Data migration** — on first load, check `_migration.readOldSnippets()`, copy to `storage.set("snippets", ...)`, call `_migration.clearOldSnippets()`, set `storage.set("migrated", "1")`
2. **Default snippets** — if no migration data and no existing storage, seed with 6 defaults (disk, memory, processes, syslog, network interfaces, open ports) — same as old plugin
3. **Session tracking** — `session.connect` sets `_activeSessionId`; `session.disconnect` clears it if matching
4. **Panel registration** — `ui.panel.register()` with `onMessage` handler

Message types handled by `onMessage`:

| Message type | Action | Returns |
|-------------|--------|---------|
| `get-snippets` | `storage.get("snippets")` | `{ type: "snippets", data: [...] }` |
| `add-snippet` | append + `storage.set` | `{ type: "ok" }` |
| `delete-snippet` | filter + `storage.set` | `{ type: "ok" }` |
| `run-snippet` | `ssh.inject(activeSessionId, command + "\n")` | `{ type: "ok" }` or `{ type: "error", message }` |
| `copy-snippet` | `ui.clipboard.copy(command)` + `ui.notify(...)` | `{ type: "ok" }` |

### `panel/index.html`

Dark-themed single-page app:

**Layout:**
- Top bar: search `<input>` + "New" `<button>`
- Snippet list: `<div>` cards, each showing label (bold), command (monospace, truncated), tag badge. On hover: "▶ Run" button + "⎘ Copy" button
- Create form: slides in when "New" clicked — Label (required), Command (textarea, required), Description (optional), Tag (optional) → "Save" button

**Bridge API in HTML:**
```js
window.pluginBridge = {
  _pending: {},
  send: function(msg) {
    return new Promise(function(resolve) {
      msg.id = Math.random().toString(36).slice(2);
      window.pluginBridge._pending[msg.id] = resolve;
      // webview_flutter 4.x JavascriptChannel named "PluginBridge"
      window.PluginBridge.postMessage(JSON.stringify(msg));
    });
  },
  receive: function(result) {
    var resolve = window.pluginBridge._pending[result.id];
    if (resolve) { resolve(result); delete window.pluginBridge._pending[result.id]; }
  }
};
```

Uses `webview_flutter` 4.x `JavascriptChannel` named `"PluginBridge"`. The WebView posts messages via `window.PluginBridge.postMessage(jsonString)`. Dart receives in the channel's `onMessageReceived` callback, calls `panel.onMessage()`, then returns the result via `controller.runJavaScript("window.pluginBridge.receive(...)")`.

---

## 6. BundledPluginInstaller

```dart
class BundledPluginInstaller {
  static Future<void> ensureInstalled(String pluginName) async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    final target = Directory('$home/.yourssh/plugins/$pluginName');
    if (target.existsSync()) return;  // already installed, don't overwrite

    target.createSync(recursive: true);
    // Copy each asset file from the bundle
    for (final asset in _assets(pluginName)) {
      final data = await rootBundle.load(asset.assetPath);
      final file = File('${target.path}/${asset.relativePath}')
        ..parent.createSync(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
  }
}
```

Called in `main.dart` before `loader.scanAndLoad()`. Only runs if the target directory does not exist — user modifications to `~/.yourssh/plugins/snippets/` are never overwritten.

Asset manifest for snippets plugin:
```
assets/bundled_plugins/snippets/plugin.json        → plugin.json
assets/bundled_plugins/snippets/index.js           → index.js
assets/bundled_plugins/snippets/panel/index.html   → panel/index.html
```

Declared in `app/pubspec.yaml` under `flutter.assets`.

---

## 7. Removing the Compiled Plugin

1. Remove `YourSSHSnippetsPlugin()` from `app/lib/plugins/plugin_registry.dart`
2. Remove `yourssh_snippets` from `app/pubspec.yaml` `dependencies` and `dependency_overrides`
3. Remove `yourssh_snippets` import from `plugin_registry.dart`
4. The `packages/yourssh_snippets/` directory is kept in the repo (not deleted) — it serves as reference for the JS rewrite and may be useful for history.

---

## 8. Error Handling

- **Migration fails**: catch exception in JS, log via `console.error()`, continue with empty/default snippets — never crash plugin load
- **Panel not found** in sidebar: guard with null check, show empty state
- **`ssh.inject` with no active session**: `onMessage` returns `{ type: "error", message: "No active session" }`, WebView shows toast notification
- **WebView load fails**: `ScriptPluginPanelScreen` shows error text with plugin path
- **`_migration.readOldSnippets()` returns corrupt JSON**: catch in JS, skip migration, seed defaults
