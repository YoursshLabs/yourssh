# Snippets Plugin JS Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the compiled `yourssh_snippets` Dart plugin with a JS script engine plugin that loads from `~/.yourssh/plugins/snippets/` at runtime, with full data migration from the old SharedPreferences key.

**Architecture:** New bridge APIs (`ssh.inject`, `ui.clipboard.copy`, `_migration.*`) are added to the script engine. A `BundledPluginInstaller` copies the snippets plugin files from app assets to disk on first run. `ScriptPluginPanelScreen` renders the plugin's WebView HTML panel. The compiled plugin is removed.

**Tech Stack:** Dart FFI + QuickJS (existing), `webview_flutter ^4.8.0` (existing in app), `shared_preferences` (existing), Flutter assets bundling.

---

## File Map

| File | Action |
|------|--------|
| `packages/yourssh_script_engine/lib/src/plugin_manifest.dart` | Add `terminal.inject`, `ui.clipboard` to known permissions |
| `app/lib/services/ssh_service.dart` | Add `sendInput(sessionId, text)` method |
| `packages/yourssh_script_engine/lib/src/bridge/terminal_inject_bridge.dart` | NEW — `ssh.inject` bridge |
| `packages/yourssh_script_engine/lib/src/bridge/migration_bridge.dart` | NEW — `_migration.*` bridge |
| `packages/yourssh_script_engine/lib/src/bridge/ui_bridge.dart` | Add `ui.clipboard.copy` |
| `packages/yourssh_script_engine/lib/src/script_engine_service.dart` | Register new bridges in `loadPlugin` |
| `packages/yourssh_script_engine/lib/yourssh_script_engine.dart` | Export new bridge types |
| `app/lib/utils/bundled_plugin_installer.dart` | NEW — copy bundled plugin assets to disk |
| `app/pubspec.yaml` | Add bundled plugin asset paths |
| `app/assets/bundled_plugins/snippets/plugin.json` | NEW — manifest |
| `app/assets/bundled_plugins/snippets/index.js` | NEW — plugin logic |
| `app/assets/bundled_plugins/snippets/panel/index.html` | NEW — WebView UI |
| `app/lib/widgets/script_plugin_panel_screen.dart` | NEW — WebView renderer |
| `app/lib/screens/main_screen.dart` | Wire script panels into sidebar + content |
| `app/lib/plugins/plugin_registry.dart` | Remove YourSSHSnippetsPlugin |
| `app/pubspec.yaml` | Remove yourssh_snippets dependency |
| `app/lib/main.dart` | Call BundledPluginInstaller before scanAndLoad |

---

## Task 1: Add permissions + `sendInput` to SshService

**Files:**
- Modify: `packages/yourssh_script_engine/lib/src/plugin_manifest.dart`
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Add two new permissions to `_kKnownPermissions`** in `packages/yourssh_script_engine/lib/src/plugin_manifest.dart`

Find the set literal `const _kKnownPermissions = {` and add:
```dart
  'terminal.inject',
  'ui.clipboard',
```

The full set should now contain 14 entries.

- [ ] **Run manifest tests to verify no regressions**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/packages/yourssh_script_engine && flutter test test/plugin_manifest_test.dart
```

Expected: 6 tests PASS.

- [ ] **Add `sendInput` to `SshService`**

In `app/lib/services/ssh_service.dart`, find the `disconnect` method (around line 406) and add `sendInput` just before it:

```dart
/// Sends [text] directly to the shell of [sessionId].
/// No-op if the session or shell is not found.
void sendInput(String sessionId, String text) {
  final shell = _shells[sessionId];
  if (shell == null) return;
  shell.write(Uint8List.fromList(text.codeUnits));
}
```

`_shells` is already a `Map<String, dynamic>` keyed by sessionId — verify the exact type by reading the field declaration at the top of the class.

- [ ] **Run app tests**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter test
```

Expected: all existing tests PASS.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add packages/yourssh_script_engine/lib/src/plugin_manifest.dart app/lib/services/ssh_service.dart
git commit -m "feat: add terminal.inject, ui.clipboard permissions and SshService.sendInput"
```

---

## Task 2: Create `TerminalInjectBridge` + `MigrationBridge`

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/bridge/terminal_inject_bridge.dart`
- Create: `packages/yourssh_script_engine/lib/src/bridge/migration_bridge.dart`

- [ ] **Create `terminal_inject_bridge.dart`**

```dart
import 'dart:convert';
import '../permission_guard.dart';
import '../js_runtime_registrar.dart';

abstract class TerminalInjectDelegate {
  void sendInput(String sessionId, String text);
}

class TerminalInjectBridge {
  final PermissionGuard _guard;
  final TerminalInjectDelegate _delegate;

  TerminalInjectBridge(this._guard, this._delegate);

  void register(JsRuntimeRegistrar rt) {
    if (!_guard.has('terminal.inject')) return;
    rt.registerHostFn('_ssh', 'inject', _inject);
  }

  String? _inject(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final sessionId = arg['sessionId'] as String;
    final text = arg['text'] as String;
    _delegate.sendInput(sessionId, text);
    return null;
  }
}
```

- [ ] **Create `migration_bridge.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

class MigrationBridge {
  static const _oldKey = 'yourssh.snippets';

  void register(JsRuntimeRegistrar rt) {
    rt.registerHostFn('_migration', 'readOldSnippets', _read);
    rt.registerHostFn('_migration', 'clearOldSnippets', _clear);
  }

  String? _read(String _) {
    final prefs = _cachedPrefs;
    if (prefs == null) return null;
    return prefs.getString(_oldKey); // null if not present
  }

  String? _clear(String _) {
    _cachedPrefs?.remove(_oldKey);
    return null;
  }

  static SharedPreferences? _cachedPrefs;

  static Future<void> warmup() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
  }
}
```

Import `JsRuntimeRegistrar` from `'../js_runtime_registrar.dart'` in both files.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add packages/yourssh_script_engine/lib/src/bridge/terminal_inject_bridge.dart packages/yourssh_script_engine/lib/src/bridge/migration_bridge.dart
git commit -m "feat: TerminalInjectBridge (ssh.inject) and MigrationBridge (_migration.*)"
```

---

## Task 3: Add `ui.clipboard.copy` + register new bridges

**Files:**
- Modify: `packages/yourssh_script_engine/lib/src/bridge/ui_bridge.dart`
- Modify: `packages/yourssh_script_engine/lib/src/script_engine_service.dart`
- Modify: `packages/yourssh_script_engine/lib/yourssh_script_engine.dart`

- [ ] **Add clipboard field + registration to `UiBridge`**

In `ui_bridge.dart`, add import at top:
```dart
import 'package:flutter/services.dart';
```

Add to the `UiBridge` class fields section — add a `_onClipboardCopy` callback (nullable, called from tests without Flutter platform channel):

Actually, use `Clipboard` directly. Add this method to `UiBridge`:

```dart
String? _clipboardCopy(String argJson) {
  final arg = json.decode(argJson) as Map<String, dynamic>;
  final text = arg['text'] as String;
  Clipboard.setData(ClipboardData(text: text));
  return null;
}
```

In `register()`, add after the `ui.panel` block:
```dart
if (_guard.has('ui.clipboard')) {
  rt.registerHostFn('_ui', 'copyToClipboard', _clipboardCopy);
}
```

- [ ] **Register new bridges in `ScriptEngineService.loadPlugin`**

In `script_engine_service.dart`, add imports at top:
```dart
import 'bridge/terminal_inject_bridge.dart';
import 'bridge/migration_bridge.dart';
```

In `loadPlugin`, after `StorageBridge(manifest.id).register(rt);`, add:

```dart
// Migration bridge — registered for all plugins, no-ops once old key is cleared
MigrationBridge().register(rt);

// Terminal inject bridge
if (sshDelegate != null) {
  TerminalInjectBridge(guard, _TerminalInjectAdapter(sshDelegate!)).register(rt);
}
```

Add a private adapter class at the bottom of `script_engine_service.dart` (outside `ScriptEngineService`):

```dart
class _TerminalInjectAdapter implements TerminalInjectDelegate {
  final SshBridgeDelegate _ssh;
  _TerminalInjectAdapter(this._ssh);

  @override
  void sendInput(String sessionId, String text) {
    // SshBridgeDelegate doesn't expose sendInput — we need a wider interface.
    // See note below.
  }
}
```

**Note:** `SshBridgeDelegate` only has `activeSessions()` and `execCommand()`. We need to extend it with `sendInput`. Add `void sendInput(String sessionId, String text);` to `SshBridgeDelegate` in `ssh_bridge.dart`. The `_SshBridgeAdapter` in `app/lib/main.dart` will implement it by calling `_sshService.sendInput(sessionId, text)`.

Update `SshBridgeDelegate` in `ssh_bridge.dart`:
```dart
abstract class SshBridgeDelegate {
  List<Map<String, dynamic>> activeSessions();
  Future<Map<String, dynamic>> execCommand(String sessionId, String command);
  void sendInput(String sessionId, String text);  // ADD THIS
}
```

Then `_TerminalInjectAdapter` simplifies to:
```dart
class _TerminalInjectAdapter implements TerminalInjectDelegate {
  final SshBridgeDelegate _ssh;
  _TerminalInjectAdapter(this._ssh);
  @override
  void sendInput(String sessionId, String text) => _ssh.sendInput(sessionId, text);
}
```

- [ ] **Update barrel export** in `yourssh_script_engine.dart`:

Add:
```dart
export 'src/bridge/terminal_inject_bridge.dart' show TerminalInjectDelegate;
export 'src/bridge/migration_bridge.dart';
```

- [ ] **Update `_SshBridgeAdapter` in `app/lib/main.dart`**

Find `_SshBridgeAdapter` class and add the `sendInput` override:
```dart
@override
void sendInput(String sessionId, String text) =>
    _getSshService().sendInput(sessionId, text);
```

- [ ] **Run all tests**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/packages/yourssh_script_engine && flutter test
```

Expected: 39 tests PASS.

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter test
```

Expected: all PASS.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add packages/yourssh_script_engine/lib/src/bridge/ui_bridge.dart packages/yourssh_script_engine/lib/src/bridge/ssh_bridge.dart packages/yourssh_script_engine/lib/src/script_engine_service.dart packages/yourssh_script_engine/lib/yourssh_script_engine.dart app/lib/main.dart
git commit -m "feat: add ui.clipboard.copy bridge and register terminal.inject + migration bridges"
```

---

## Task 4: Create `BundledPluginInstaller` + declare assets

**Files:**
- Create: `app/lib/utils/bundled_plugin_installer.dart`
- Modify: `app/pubspec.yaml`

- [ ] **Create `app/lib/utils/bundled_plugin_installer.dart`**

```dart
import 'dart:io';
import 'package:flutter/services.dart';

class BundledPluginInstaller {
  static const _bundledPlugins = {
    'snippets': [
      'plugin.json',
      'index.js',
      'panel/index.html',
    ],
  };

  /// Copies bundled plugin assets to ~/.yourssh/plugins/<name>/ if not already present.
  /// Never overwrites an existing installation.
  static Future<void> ensureInstalled(String pluginName) async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    final target = Directory('$home/.yourssh/plugins/$pluginName');
    if (target.existsSync()) return;

    target.createSync(recursive: true);
    final files = _bundledPlugins[pluginName] ?? [];
    for (final relativePath in files) {
      final assetPath = 'assets/bundled_plugins/$pluginName/$relativePath';
      final data = await rootBundle.load(assetPath);
      final outFile = File('${target.path}/$relativePath')
        ..parent.createSync(recursive: true);
      await outFile.writeAsBytes(data.buffer.asUint8List());
    }
  }
}
```

- [ ] **Add asset declarations to `app/pubspec.yaml`**

Find the `assets:` section (currently has `- assets/monaco_editor.html`, etc.) and add:

```yaml
    - assets/bundled_plugins/snippets/plugin.json
    - assets/bundled_plugins/snippets/index.js
    - assets/bundled_plugins/snippets/panel/index.html
```

The actual asset files will be created in Task 5. For now just declare them.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add app/lib/utils/bundled_plugin_installer.dart app/pubspec.yaml
git commit -m "feat: BundledPluginInstaller + declare bundled plugin assets in pubspec"
```

---

## Task 5: Create Snippets JS plugin files

**Files:**
- Create: `app/assets/bundled_plugins/snippets/plugin.json`
- Create: `app/assets/bundled_plugins/snippets/index.js`
- Create: `app/assets/bundled_plugins/snippets/panel/index.html`

- [ ] **Create directory structure**

```bash
mkdir -p /Users/thangnguyen/Documents/Personal/yourssh/app/assets/bundled_plugins/snippets/panel
```

- [ ] **Create `plugin.json`**

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

- [ ] **Create `index.js`**

```js
'use strict';

var DEFAULTS = [
  { id: 'd1', label: 'Disk usage', command: 'df -h', description: 'Show disk usage per filesystem', tag: 'system' },
  { id: 'd2', label: 'Memory', command: 'free -h', description: 'Show memory and swap usage', tag: 'system' },
  { id: 'd3', label: 'Top processes', command: 'ps aux --sort=-%cpu | head -20', description: 'CPU-sorted process list', tag: 'system' },
  { id: 'd4', label: 'Syslog tail', command: 'tail -f /var/log/syslog', description: 'Follow system log', tag: 'logs' },
  { id: 'd5', label: 'Network interfaces', command: 'ip addr show', description: 'List network interfaces', tag: 'network' },
  { id: 'd6', label: 'Open ports', command: 'ss -tlnp', description: 'Show listening TCP ports', tag: 'network' }
];

var _activeSessionId = null;

// ── Data helpers ──────────────────────────────────────────────────────────────

function getSnippets() {
  var raw = _storage.get(JSON.stringify({ key: 'snippets' }));
  if (raw === null || raw === 'null') return DEFAULTS.slice();
  try {
    var parsed = JSON.parse(raw);
    return JSON.parse(parsed.value);
  } catch (e) {
    return DEFAULTS.slice();
  }
}

function saveSnippets(list) {
  _storage.set(JSON.stringify({ key: 'snippets', value: JSON.stringify(list) }));
}

// ── One-time data migration from old SharedPreferences key ────────────────────

function migrateIfNeeded() {
  try {
    var alreadyMigrated = _storage.get(JSON.stringify({ key: 'migrated' }));
    if (alreadyMigrated !== null && alreadyMigrated !== 'null') return;

    var oldRaw = _migration.readOldSnippets('null');
    if (oldRaw !== null && oldRaw !== 'null') {
      // Old format: JSON array of {id, label, command, description, tag}
      var oldData = JSON.parse(oldRaw);
      if (Array.isArray(oldData) && oldData.length > 0) {
        saveSnippets(oldData);
        _migration.clearOldSnippets('null');
        console.log('[snippets] Migrated ' + oldData.length + ' snippets from old storage');
      }
    }

    _storage.set(JSON.stringify({ key: 'migrated', value: '1' }));
  } catch (e) {
    console.error('[snippets] Migration error: ' + e);
    // Never crash — continue with defaults
  }
}

// ── Session tracking ──────────────────────────────────────────────────────────

plugin.on('session.connect', function(ctx) {
  _activeSessionId = ctx.sessionId;
});

plugin.on('session.disconnect', function(ctx) {
  if (_activeSessionId === ctx.sessionId) {
    _activeSessionId = null;
  }
});

// ── Panel registration ────────────────────────────────────────────────────────

migrateIfNeeded();

ui.panel.register({
  title: 'Snippets',
  icon: 'code',
  webviewEntry: 'panel/index.html',
  onMessage: function(msg) {
    try {
      if (msg.type === 'get-snippets') {
        return { type: 'snippets', data: getSnippets() };
      }

      if (msg.type === 'add-snippet') {
        var list = getSnippets();
        var snippet = msg.snippet;
        snippet.id = 's' + Date.now() + Math.random().toString(36).slice(2, 6);
        list.push(snippet);
        saveSnippets(list);
        return { type: 'ok' };
      }

      if (msg.type === 'delete-snippet') {
        var list = getSnippets().filter(function(s) { return s.id !== msg.id; });
        saveSnippets(list);
        return { type: 'ok' };
      }

      if (msg.type === 'run-snippet') {
        if (!_activeSessionId) {
          return { type: 'error', message: 'No active SSH session. Connect to a host first.' };
        }
        _ssh.inject(JSON.stringify({ sessionId: _activeSessionId, text: msg.command + '\n' }));
        return { type: 'ok' };
      }

      if (msg.type === 'copy-snippet') {
        _ui.copyToClipboard(JSON.stringify({ text: msg.command }));
        _ui.notify(JSON.stringify({ message: 'Copied to clipboard', type: 'info' }));
        return { type: 'ok' };
      }

      return { type: 'error', message: 'Unknown message type: ' + msg.type };
    } catch (e) {
      console.error('[snippets] onMessage error: ' + e);
      return { type: 'error', message: String(e) };
    }
  }
});
```

**Note:** `_storage.get`, `_storage.set`, `_ui.notify`, `_ui.copyToClipboard`, `_ssh.inject`, `_migration.readOldSnippets`, `_migration.clearOldSnippets` are all synchronous bridge calls registered by the engine. The `onMessage` handler is called from Dart — it does NOT have `async/await` here because the JS bridge functions are sync. The `ui.panel.register` `onMessage` is invoked from Dart asynchronously, but the handler itself runs sync JS.

- [ ] **Create `panel/index.html`**

Full self-contained dark-themed single-page app. All CSS and JS inline:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Snippets</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  background: #1a1a2e;
  color: #e2e8f0;
  height: 100vh;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}
.topbar {
  display: flex;
  gap: 8px;
  padding: 12px;
  background: #16213e;
  border-bottom: 1px solid #2d3748;
  flex-shrink: 0;
}
.search {
  flex: 1;
  background: #1a1a2e;
  border: 1px solid #2d3748;
  border-radius: 6px;
  padding: 6px 10px;
  color: #e2e8f0;
  font-size: 13px;
  outline: none;
}
.search:focus { border-color: #4a9eff; }
.btn {
  background: #4a9eff;
  color: #fff;
  border: none;
  border-radius: 6px;
  padding: 6px 14px;
  font-size: 13px;
  cursor: pointer;
  white-space: nowrap;
}
.btn:hover { background: #3a8eef; }
.btn-sm {
  background: #2d3748;
  color: #a0aec0;
  border: none;
  border-radius: 4px;
  padding: 3px 8px;
  font-size: 11px;
  cursor: pointer;
}
.btn-sm:hover { background: #4a5568; color: #e2e8f0; }
.btn-run { background: #22c55e22; color: #22c55e; }
.btn-run:hover { background: #22c55e44; }
.btn-danger { background: #ef444422; color: #ef4444; }
.btn-danger:hover { background: #ef444444; }
.list {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
}
.list::-webkit-scrollbar { width: 4px; }
.list::-webkit-scrollbar-thumb { background: #2d3748; border-radius: 2px; }
.card {
  background: #16213e;
  border: 1px solid #2d3748;
  border-radius: 8px;
  padding: 10px 12px;
  margin-bottom: 6px;
  cursor: pointer;
  transition: border-color 0.15s;
}
.card:hover { border-color: #4a5568; }
.card-header { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
.card-label { font-weight: 600; font-size: 13px; color: #e2e8f0; flex: 1; }
.card-actions { display: flex; gap: 4px; opacity: 0; transition: opacity 0.15s; }
.card:hover .card-actions { opacity: 1; }
.card-cmd {
  font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
  font-size: 12px;
  color: #a0aec0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.card-meta { display: flex; align-items: center; gap: 6px; margin-top: 4px; }
.card-desc { font-size: 11px; color: #718096; flex: 1; }
.tag {
  background: #2d3748;
  color: #a0aec0;
  border-radius: 3px;
  padding: 1px 6px;
  font-size: 10px;
}
.empty {
  text-align: center;
  color: #4a5568;
  padding: 40px 20px;
  font-size: 13px;
}
.form-overlay {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex; align-items: center; justify-content: center;
  z-index: 100;
}
.form-overlay.hidden { display: none; }
.form-card {
  background: #16213e;
  border: 1px solid #2d3748;
  border-radius: 10px;
  padding: 20px;
  width: 400px;
  max-width: 90vw;
}
.form-title { font-size: 15px; font-weight: 600; margin-bottom: 16px; }
.form-group { margin-bottom: 12px; }
.form-label { font-size: 12px; color: #a0aec0; margin-bottom: 4px; display: block; }
.form-input, .form-textarea {
  width: 100%;
  background: #1a1a2e;
  border: 1px solid #2d3748;
  border-radius: 6px;
  padding: 7px 10px;
  color: #e2e8f0;
  font-size: 13px;
  outline: none;
  font-family: inherit;
}
.form-textarea { font-family: 'Menlo', monospace; min-height: 80px; resize: vertical; }
.form-input:focus, .form-textarea:focus { border-color: #4a9eff; }
.form-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 16px; }
.toast {
  position: fixed; bottom: 16px; left: 50%; transform: translateX(-50%);
  background: #22c55e; color: #fff;
  padding: 8px 16px; border-radius: 6px;
  font-size: 13px; z-index: 200;
  opacity: 0; transition: opacity 0.2s;
  pointer-events: none;
}
.toast.show { opacity: 1; }
.toast.error { background: #ef4444; }
</style>
</head>
<body>

<div class="topbar">
  <input class="search" id="search" type="text" placeholder="Search snippets…" oninput="render()">
  <button class="btn" onclick="showForm()">+ New</button>
</div>

<div class="list" id="list"></div>

<div class="form-overlay hidden" id="overlay" onclick="overlayClick(event)">
  <div class="form-card">
    <div class="form-title">New Snippet</div>
    <div class="form-group">
      <label class="form-label">Label *</label>
      <input class="form-input" id="f-label" placeholder="e.g. Check disk usage">
    </div>
    <div class="form-group">
      <label class="form-label">Command *</label>
      <textarea class="form-textarea" id="f-cmd" placeholder="e.g. df -h"></textarea>
    </div>
    <div class="form-group">
      <label class="form-label">Description</label>
      <input class="form-input" id="f-desc" placeholder="Optional description">
    </div>
    <div class="form-group">
      <label class="form-label">Tag</label>
      <input class="form-input" id="f-tag" placeholder="e.g. system, network, logs">
    </div>
    <div class="form-actions">
      <button class="btn-sm" onclick="hideForm()" style="padding:6px 14px;font-size:13px;">Cancel</button>
      <button class="btn" onclick="saveSnippet()">Save</button>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
// ── Bridge ────────────────────────────────────────────────────────────────────
window.pluginBridge = {
  _pending: {},
  send: function(msg) {
    return new Promise(function(resolve) {
      msg.id = Math.random().toString(36).slice(2);
      window.pluginBridge._pending[msg.id] = resolve;
      window.PluginBridge.postMessage(JSON.stringify(msg));
    });
  },
  receive: function(resultStr) {
    var result = typeof resultStr === 'string' ? JSON.parse(resultStr) : resultStr;
    var resolve = window.pluginBridge._pending[result.id];
    if (resolve) { resolve(result); delete window.pluginBridge._pending[result.id]; }
  }
};

// ── State ─────────────────────────────────────────────────────────────────────
var snippets = [];

async function loadSnippets() {
  var r = await pluginBridge.send({ type: 'get-snippets' });
  snippets = r.data || [];
  render();
}

function render() {
  var q = document.getElementById('search').value.toLowerCase();
  var filtered = snippets.filter(function(s) {
    return !q || (s.label + s.command + (s.tag || '')).toLowerCase().includes(q);
  });
  var el = document.getElementById('list');
  if (!filtered.length) {
    el.innerHTML = '<div class="empty">' + (q ? 'No snippets match "' + q + '"' : 'No snippets yet. Click + New to add one.') + '</div>';
    return;
  }
  el.innerHTML = filtered.map(function(s) {
    return '<div class="card" id="card-' + s.id + '">' +
      '<div class="card-header">' +
        '<span class="card-label">' + esc(s.label) + '</span>' +
        '<div class="card-actions">' +
          '<button class="btn-sm btn-run" onclick="runSnippet(event,\'' + s.id + '\')">▶ Run</button>' +
          '<button class="btn-sm" onclick="copySnippet(event,\'' + s.id + '\')">⎘ Copy</button>' +
          '<button class="btn-sm btn-danger" onclick="deleteSnippet(event,\'' + s.id + '\')">✕</button>' +
        '</div>' +
      '</div>' +
      '<div class="card-cmd">' + esc(s.command) + '</div>' +
      '<div class="card-meta">' +
        (s.description ? '<span class="card-desc">' + esc(s.description) + '</span>' : '<span class="card-desc"></span>') +
        (s.tag ? '<span class="tag">' + esc(s.tag) + '</span>' : '') +
      '</div>' +
    '</div>';
  }).join('');
}

function esc(s) {
  return (s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Actions ───────────────────────────────────────────────────────────────────
async function runSnippet(e, id) {
  e.stopPropagation();
  var s = snippets.find(function(x) { return x.id === id; });
  if (!s) return;
  var r = await pluginBridge.send({ type: 'run-snippet', command: s.command });
  if (r.type === 'error') showToast(r.message, true);
  else showToast('Command sent to terminal');
}

async function copySnippet(e, id) {
  e.stopPropagation();
  var s = snippets.find(function(x) { return x.id === id; });
  if (!s) return;
  await pluginBridge.send({ type: 'copy-snippet', command: s.command });
  showToast('Copied to clipboard');
}

async function deleteSnippet(e, id) {
  e.stopPropagation();
  if (!confirm('Delete this snippet?')) return;
  await pluginBridge.send({ type: 'delete-snippet', id: id });
  snippets = snippets.filter(function(s) { return s.id !== id; });
  render();
}

function showForm() {
  document.getElementById('overlay').classList.remove('hidden');
  document.getElementById('f-label').value = '';
  document.getElementById('f-cmd').value = '';
  document.getElementById('f-desc').value = '';
  document.getElementById('f-tag').value = '';
  setTimeout(function() { document.getElementById('f-label').focus(); }, 50);
}

function hideForm() {
  document.getElementById('overlay').classList.add('hidden');
}

function overlayClick(e) {
  if (e.target === document.getElementById('overlay')) hideForm();
}

async function saveSnippet() {
  var label = document.getElementById('f-label').value.trim();
  var cmd = document.getElementById('f-cmd').value.trim();
  if (!label || !cmd) { showToast('Label and command are required', true); return; }
  var snippet = {
    label: label,
    command: cmd,
    description: document.getElementById('f-desc').value.trim(),
    tag: document.getElementById('f-tag').value.trim()
  };
  var r = await pluginBridge.send({ type: 'add-snippet', snippet: snippet });
  if (r.type === 'error') { showToast(r.message, true); return; }
  hideForm();
  await loadSnippets();
}

function showToast(msg, isError) {
  var el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'toast show' + (isError ? ' error' : '');
  setTimeout(function() { el.classList.remove('show'); }, 2500);
}

// ── Init ──────────────────────────────────────────────────────────────────────
loadSnippets();
</script>
</body>
</html>
```

- [ ] **Verify files exist**

```bash
ls /Users/thangnguyen/Documents/Personal/yourssh/app/assets/bundled_plugins/snippets/
ls /Users/thangnguyen/Documents/Personal/yourssh/app/assets/bundled_plugins/snippets/panel/
```

Expected: `plugin.json  index.js` in first dir, `index.html` in panel/.

- [ ] **Run `flutter pub get` to register new assets**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter pub get
```

Expected: exits 0.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add app/assets/bundled_plugins/
git commit -m "feat: add bundled snippets JS plugin (plugin.json + index.js + panel/index.html)"
```

---

## Task 6: Create `ScriptPluginPanelScreen`

**Files:**
- Create: `app/lib/widgets/script_plugin_panel_screen.dart`

- [ ] **Create the file**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

class ScriptPluginPanelScreen extends StatefulWidget {
  final PluginPanelEntry panel;

  const ScriptPluginPanelScreen({super.key, required this.panel});

  @override
  State<ScriptPluginPanelScreen> createState() => _ScriptPluginPanelScreenState();
}

class _ScriptPluginPanelScreenState extends State<ScriptPluginPanelScreen> {
  late final WebViewController _controller;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PluginBridge',
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loaded = true),
        onWebResourceError: (e) =>
            setState(() => _error = 'WebView error: ${e.description}'),
      ));

    _loadPanel();
  }

  Future<void> _loadPanel() async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    final htmlPath =
        '$home/.yourssh/plugins/${widget.panel.pluginId}/${widget.panel.webviewEntry}';
    final file = File(htmlPath);
    if (!file.existsSync()) {
      setState(() => _error = 'Panel file not found:\n$htmlPath');
      return;
    }
    final html = await file.readAsString();
    await _controller.loadHtmlString(html, baseUrl: 'file://$home/.yourssh/plugins/${widget.panel.pluginId}/panel/');
  }

  void _onBridgeMessage(JavaScriptMessage message) async {
    Map<String, dynamic> msg;
    try {
      msg = json.decode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final id = msg['id'] as String?;
    Map<String, dynamic> result;
    try {
      final response = await widget.panel.onMessage(msg);
      result = response != null
          ? (json.decode(response) as Map<String, dynamic>)
          : {'type': 'ok'};
    } catch (e) {
      result = {'type': 'error', 'message': e.toString()};
    }
    if (id != null) result['id'] = id;

    if (!mounted) return;
    final encoded = json.encode(result).replaceAll("'", "\\'");
    await _controller
        .runJavaScript("window.pluginBridge.receive('$encoded')");
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_loaded)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
```

- [ ] **Verify it compiles**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter analyze lib/widgets/script_plugin_panel_screen.dart 2>&1 | grep -E "error:|warning:" | head -10
```

Expected: no errors.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add app/lib/widgets/script_plugin_panel_screen.dart
git commit -m "feat: ScriptPluginPanelScreen — WebView renderer for script plugin panels"
```

---

## Task 7: Wire sidebar + content in MainScreen; remove compiled Snippets plugin

**Files:**
- Modify: `app/lib/screens/main_screen.dart`
- Modify: `app/lib/plugins/plugin_registry.dart`
- Modify: `app/pubspec.yaml`

### Part A: Remove compiled Snippets plugin

- [ ] **Remove from `plugin_registry.dart`**

In `app/lib/plugins/plugin_registry.dart`:
1. Remove `import 'package:yourssh_snippets/yourssh_snippets.dart';`
2. Remove `YourSSHSnippetsPlugin(),` from `kRegisteredPlugins`

- [ ] **Remove from `app/pubspec.yaml`**

Remove these lines from both `dependencies:` and `dependency_overrides:`:
```yaml
  yourssh_snippets:
    path: ../packages/yourssh_snippets
```

- [ ] **Run `flutter pub get`**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter pub get
```

Expected: exits 0, `yourssh_snippets` no longer in output.

### Part B: Wire `_activeScriptPanel` into MainScreen

- [ ] **Add `_activeScriptPanel` field and reset logic**

In `_MainScreenState`, add alongside `_activePluginId`:
```dart
String? _activeScriptPanel;
```

Wherever `_activePluginId = null` is set in `onSelect` callback (line ~533), also add:
```dart
_activeScriptPanel = null;
```

- [ ] **Add `onSelectScriptPanel` callback to `_Sidebar`**

In the `_Sidebar` widget constructor and class, add:
```dart
final ValueChanged<String> onSelectScriptPanel;
```

Pass it in `_MainScreenState` where `_Sidebar` is instantiated:
```dart
onSelectScriptPanel: (pluginId) {
  setState(() {
    _activeScriptPanel = pluginId;
    _activePluginId = null;
    _viewingTerminal = false;
    _sidePanel = _SidePanel.none;
  });
},
```

- [ ] **Add script panel nav items after compiled plugins in `_Sidebar.build`**

In `_Sidebar.build`, find the line that maps `enabledPlugins` (line ~738):
```dart
...context.watch<PluginProvider>().enabledPlugins.map(
  (plugin) => _pluginNavItem(context, plugin),
),
```

After the closing `,` of that spread, add script panel items:
```dart
...context.watch<PluginUiRegistry>().panels.map(
  (panel) => _ScriptPanelNavItem(
    panel: panel,
    isActive: activeScriptPanel == panel.pluginId,
    onTap: () => onSelectScriptPanel(panel.pluginId),
  ),
),
```

Add `final String? activeScriptPanel;` to `_Sidebar`'s constructor parameters, and pass `activeScriptPanel: _activeScriptPanel` from `_MainScreenState` where `_Sidebar` is built.

- [ ] **Add `_ScriptPanelNavItem` widget**

After the existing `_PluginNavItem` widget class (around line 794), add:

```dart
class _ScriptPanelNavItem extends StatelessWidget {
  final PluginPanelEntry panel;
  final bool isActive;
  final VoidCallback onTap;

  const _ScriptPanelNavItem({
    required this.panel,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _NavItem(
      icon: Icons.code_outlined,
      label: panel.title,
      selected: isActive,
      onTap: onTap,
    );
  }
}
```

Add import at top: `import 'package:yourssh_script_engine/yourssh_script_engine.dart';` (if not already present) and `import '../widgets/script_plugin_panel_screen.dart';`.

- [ ] **Wire content area**

In `_buildContent`, before the existing `if (_activePluginId != null)` block (line ~645), add:

```dart
// Script plugin panel
if (_activeScriptPanel != null) {
  final registry = context.watch<PluginUiRegistry>();
  final panels = registry.panels.where((p) => p.pluginId == _activeScriptPanel);
  if (panels.isNotEmpty) {
    return ScriptPluginPanelScreen(panel: panels.first);
  }
  // Panel unregistered (plugin was unloaded) — reset
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() => _activeScriptPanel = null);
  });
  return const SizedBox.shrink();
}
```

- [ ] **Run `flutter analyze`**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter analyze 2>&1 | grep -E "^.*error:" | head -20
```

Fix any issues. Common: missing imports, `_Sidebar` constructor signature mismatch.

- [ ] **Run app tests**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter test
```

Expected: all PASS.

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add app/lib/screens/main_screen.dart app/lib/plugins/plugin_registry.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat: wire script plugin panels into sidebar; remove compiled Snippets plugin"
```

---

## Task 8: Wire BundledPluginInstaller in main.dart + end-to-end verify

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Add BundledPluginInstaller call in `main.dart`**

Add import at top:
```dart
import 'utils/bundled_plugin_installer.dart';
```

In `initState` (or wherever `loader.scanAndLoad()` is called — search for `scanAndLoad`), add BEFORE `scanAndLoad`:

```dart
// Install bundled plugins to ~/.yourssh/plugins/ on first run
await BundledPluginInstaller.ensureInstalled('snippets');
```

Also add `MigrationBridge.warmup()` call before `scanAndLoad` (so SharedPreferences is cached before any plugin loads):

```dart
await MigrationBridge.warmup();
```

Add import: `import 'package:yourssh_script_engine/yourssh_script_engine.dart';` (already likely present).

- [ ] **Run `flutter analyze`**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter analyze 2>&1 | grep -c "error:" || echo "0 errors"
```

Expected: 0 errors.

- [ ] **Run all tests**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter test 2>&1 | tail -5
cd /Users/thangnguyen/Documents/Personal/yourssh/packages/yourssh_script_engine && flutter test 2>&1 | tail -5
```

Both expected: all PASS.

- [ ] **Manual smoke test**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh/app && flutter run -d macos
```

Verify:
1. App launches without crash
2. `~/.yourssh/plugins/snippets/` exists after launch
3. "Snippets" appears in sidebar under TOOLS (alongside DevOps, Web Tools)
4. Clicking "Snippets" opens WebView with snippet list
5. Default 6 snippets are shown
6. Can add a new snippet via "+ New" form
7. Can copy a snippet command to clipboard
8. Can delete a snippet
9. Connect to a host → "▶ Run" button on a snippet sends command to terminal

- [ ] **Commit**

```bash
cd /Users/thangnguyen/Documents/Personal/yourssh
git add app/lib/main.dart
git commit -m "feat: wire BundledPluginInstaller and MigrationBridge.warmup into main.dart"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|-----------------|------|
| `terminal.inject` + `ui.clipboard` permissions | Task 1 |
| `SshService.sendInput()` | Task 1 |
| `TerminalInjectBridge` | Task 2 |
| `MigrationBridge` (_migration.readOldSnippets / clearOldSnippets) | Task 2 |
| `UiBridge.ui.clipboard.copy` | Task 3 |
| New bridges registered in ScriptEngineService | Task 3 |
| `SshBridgeDelegate.sendInput()` + _SshBridgeAdapter impl | Task 3 |
| `BundledPluginInstaller` | Task 4 |
| Asset declarations in pubspec | Task 4 |
| `plugin.json` | Task 5 |
| `index.js` with migration + defaults + onMessage | Task 5 |
| `panel/index.html` dark-themed UI | Task 5 |
| `ScriptPluginPanelScreen` WebView renderer | Task 6 |
| Sidebar: script panels after compiled plugins | Task 7 |
| Content area: `_activeScriptPanel` switch | Task 7 |
| Remove compiled Snippets plugin | Task 7 |
| `BundledPluginInstaller.ensureInstalled` in main | Task 8 |
| `MigrationBridge.warmup` before scanAndLoad | Task 8 |
| Error handling (migration fail, no session, WebView fail) | Tasks 5 + 6 |
