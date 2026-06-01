> Full guide also available at [`docs/plugin-authoring-guide.md`](../blob/master/docs/plugin-authoring-guide.md) in the repository.

# YourSSH Plugin Authoring Guide

A complete guide to writing script plugins for YourSSH — no app rebuild required, just create a folder and write JS.

---

## Table of Contents

1. [How it works](#1-how-it-works)
2. [Plugin structure](#2-plugin-structure)
3. [Manifest (plugin.json)](#3-manifest-pluginjson)
4. [API: Hook events](#4-api-hook-events)
5. [API: Bridge functions](#5-api-bridge-functions)
6. [API: Native panel messages](#6-api-native-panel-messages)
7. [Lifecycle & hot-reload](#7-lifecycle--hot-reload)
8. [Security & permissions](#8-security--permissions)
9. [Examples](#9-examples)
10. [Debugging](#10-debugging)
11. [Known limitations](#11-known-limitations)
12. [Pre-publish checklist](#12-pre-publish-checklist)

---

## 1. How it works

YourSSH runs each plugin in an **isolated JavaScript runtime** (QuickJS). On startup the app scans `~/.yourssh/plugins/`, loads each plugin, and injects a `plugin` object into the JS context.

Plugins register handlers via `plugin.on(event, handler)`. The app fires events at the right moments (terminal data, session connect, etc.) — handlers are called synchronously or asynchronously depending on the event.

```
App (Dart)          Plugin (JavaScript)
    │                       │
    │──terminal data──►  plugin.on("terminal.output", handler)
    │◄──transformed data──  return modifiedData
    │
    │──session opens──►  plugin.on("session.connect", handler)
    │                       │
    │──ssh.exec()────►   ssh.exec(sessionId, "whoami")
    │◄──result────────       Promise<{stdout, stderr, exitCode}>
```

---

## 2. Plugin structure

```
~/.yourssh/plugins/
  my-plugin/
    plugin.json     ← required: manifest
    index.js        ← required: entry point
    lib/
      helpers.js    ← optional: helper files
```

A plugin is a **directory** inside `~/.yourssh/plugins/`. The app identifies it via `plugin.json`. No install step, no build step.

---

## 3. Manifest (`plugin.json`)

```json
{
  "id": "dev.yourname.myplugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": [
    "terminal.transform",
    "session.observe"
  ]
}
```

### Required fields

| Field | Description |
|-------|-------------|
| `id` | Unique reverse-domain ID. Pattern: `^[a-z0-9][a-z0-9._\-]{0,63}$` |
| `name` | Display name shown in UI |
| `version` | Semantic version: `MAJOR.MINOR.PATCH` |
| `entry` | JS entry point (relative to plugin folder) |
| `minAppVersion` | Minimum YourSSH version required |
| `permissions` | List of permissions needed (see section 8) |

### ID format

- Must start with a lowercase letter or digit
- Allowed characters: `a-z`, `0-9`, `.`, `_`, `-`
- Maximum 64 characters
- Follow reverse-domain convention: `dev.yourname.pluginname`

---

## 4. API: Hook events

Plugins register handlers via `plugin.on(event, handler)`.

### Terminal events

#### `terminal.output` — Transform terminal output

> **Required permission:** `terminal.transform` (to modify) or `terminal.read` (observe-only)

```js
plugin.on("terminal.output", function(ctx) {
  // ctx.sessionId : string — SSH session ID
  // ctx.data      : string — raw terminal output text (may contain ANSI escape codes)

  // Return string → replace data
  // Return null / undefined → pass-through (no change)
  return ctx.data.replace(/ERROR/g, "\x1b[31mERROR\x1b[0m");
});
```

**Hot path:** Called for every chunk of data from the SSH server. Must be **synchronous** and **fast** (< 5ms). Do not perform I/O or heavy computation here.

---

#### `terminal.input` — Intercept user keystrokes

> **Required permission:** `terminal.intercept`

```js
plugin.on("terminal.input", function(ctx) {
  // ctx.sessionId : string
  // ctx.data      : string — keystroke(s) about to be sent to the SSH server

  // Return false → cancel (keystroke is not sent)
  // Return string → modify and send that string instead
  // Return null / undefined → pass-through

  if (ctx.data.trim() === "rm -rf /") return false; // block
  return ctx.data; // pass-through
});
```

**Hot path:** Must be synchronous.

---

### Session events

#### `session.connect` — Session connected successfully

> **Required permission:** `session.observe`

```js
plugin.on("session.connect", function(ctx) {
  // ctx.sessionId : string
  // ctx.host      : string — hostname
  // ctx.username  : string
  // ctx.port      : number
  console.log("Connected to " + ctx.username + "@" + ctx.host);
});
```

Async handlers are allowed (handler does not block the terminal).

---

#### `session.disconnect` — Session closed

> **Required permission:** `session.observe`

```js
plugin.on("session.disconnect", function(ctx) {
  // ctx.sessionId : string
  ui.statusbar.remove("my-status-" + ctx.sessionId);
});
```

---

#### `session.connect.before` — Before connect (can cancel)

> **Required permission:** `session.control`

```js
plugin.on("session.connect.before", function(ctx) {
  if (ctx.host === "blocked-host.com") return false; // cancel connect
  // return nothing → allow
});
```

---

### Command events

#### `command.before` — Before `ssh.exec()` runs

> **Required permission:** `command.intercept`

```js
plugin.on("command.before", function(ctx) {
  // ctx.sessionId : string
  // ctx.command   : string — command about to run

  // Return false → cancel
  // Return string → replace command
  console.log("Running: " + ctx.command);
  return ctx.command;
});
```

---

#### `command.after` — After `ssh.exec()` completes

> **Required permission:** `command.intercept`

```js
plugin.on("command.after", function(ctx) {
  // ctx.sessionId : string
  // ctx.command   : string — command that ran
  // ctx.stdout    : string
  // ctx.stderr    : string
  // ctx.exitCode  : number
  if (ctx.exitCode !== 0) {
    console.error("[plugin] Command failed: " + ctx.command);
  }
});
```

---

### Event summary

| Event | Permission | Sync | Can cancel | Can transform |
|-------|-----------|------|-----------|---------------|
| `terminal.output` | `terminal.transform` | ✅ | ❌ | ✅ |
| `terminal.input` | `terminal.intercept` | ✅ | ✅ | ✅ |
| `session.connect` | `session.observe` | ❌ | ❌ | ❌ |
| `session.connect.before` | `session.control` | ✅ | ✅ | ❌ |
| `session.disconnect` | `session.observe` | ❌ | ❌ | ❌ |
| `command.before` | `command.intercept` | ✅ | ✅ | ✅ |
| `command.after` | `command.intercept` | ❌ | ❌ | ❌ |

---

## 5. API: Bridge functions

Bridge functions let plugins call into the app. Available only when the corresponding permission is granted.

### `ssh` — SSH operations

#### `ssh.sessions()` → `Array`

> **Permission:** `session.observe` or `ssh.exec`

```js
const sessions = ssh.sessions();
// Returns:
// [
//   {
//     sessionId: "abc123",
//     host: "myserver.com",
//     username: "ubuntu",
//     port: 22,
//     connected: true
//   }
// ]
```

#### `ssh.inject(sessionId, text)` — Send text to terminal shell

> **Permission:** `terminal.inject`

```js
// Sends the text directly into the active shell (as if the user typed it)
ssh.inject(sessionId, "ls -la\n");  // \n submits the command
```

---

### `sftp` — File operations

> **Permission:** `sftp.read` (for list/read) or `sftp.write` (for write/delete/mkdir)

```js
// List remote directory
const entries = await sftp.list(sessionId, "/var/log");
// entries: [{ name, isDir, size, modified }]

// Read remote file content
const content = await sftp.read(sessionId, "/etc/hostname");

// Write to remote file
await sftp.write(sessionId, "/tmp/test.txt", "hello world");

// Delete remote file
await sftp.delete(sessionId, "/tmp/test.txt");

// Create remote directory
await sftp.mkdir(sessionId, "/tmp/newdir");
```

---

### `storage` — Persistent key-value store

> **Permission:** None — always available. Auto-namespaced by plugin id.

```js
// Save
await storage.set("mykey", "myvalue");

// Load
const val = await storage.get("mykey");
if (val !== null) console.log(val.value);

// Delete
await storage.delete("mykey");
```

Keys are automatically namespaced as `plugin::<id>::storage::<key>` — no collision risk with other plugins.

---

### `ui` — User interface

#### `ui.notify(message, options)` — Desktop notification

> **Permission:** `ui.notify`

```js
ui.notify("Upload complete!", { type: "info" });
// type: "info" | "warning" | "error"
```

#### `ui.statusbar.*` — Status bar items

> **Permission:** `ui.statusbar`

```js
// Add item
ui.statusbar.add("my-item", {
  label: "CPU: --",
  tooltip: "Remote CPU usage"
});

// Update label
ui.statusbar.update("my-item", { label: "CPU: 42%" });

// Remove
ui.statusbar.remove("my-item");
```

Status bar items appear at the bottom of the app window.

#### `ui.panel.register(config)` — Sidebar panel (WebView)

> **Permission:** `ui.panel`

```js
ui.panel.register({
  title: "My Panel",
  icon: "monitor",
  webviewEntry: "panel/index.html",  // relative to plugin folder
  onMessage: function(msg) {
    if (msg.type === "get-data") {
      return { type: "data", value: "hello" };
    }
  }
});
```

The panel `onMessage` handler must be **synchronous**. For async SSH/SFTP operations from panel HTML, use [native panel messages](#6-api-native-panel-messages) instead.

#### `ui.clipboard.copy(text)` — Copy to clipboard

> **Permission:** `ui.clipboard`

```js
ui.clipboard.copy(snippet.command);
ui.notify("Copied to clipboard", { type: "info" });
```

#### `ui.addCommand(config)` — Register command palette entry

> **Permission:** `ui.statusbar` or `ui.panel`

```js
ui.addCommand({
  id: "clear-logs",
  label: "Clear Remote Logs",
  keybinding: "Ctrl+Shift+L"  // optional
});
```

The command appears in the command palette. **Note:** Command click handler is not yet implemented (see [Known limitations](#11-known-limitations)).

---

### `console` — Debug logging

> **Permission:** None — always available.

```js
console.log("debug message");
console.warn("warning");
console.error("error message");
```

Logs appear in the **Plugin Console** (Settings → Script Plugins → plugin → Console). Multiple arguments are supported:

```js
console.log("Sessions:", sessions.length, "connected");
```

---

## 6. API: Native panel messages

Plugin panel HTML can send **native messages** to perform SSH/SFTP operations without JS async limitations. Dart handles them directly and returns the result to the WebView.

Use via `pluginBridge.send()` from `panel/index.html`:

### `ssh-exec` — Run SSH command

```js
const r = await pluginBridge.send({
  type: 'ssh-exec',
  sessionId: 's1',
  command: 'uname -a'
});
// r = { type: 'exec-result', stdout: '...', stderr: '', exitCode: 0 }
if (r.exitCode !== 0) console.error(r.stderr);
else display(r.stdout);
```

### `ssh-sessions` — List active sessions

```js
const r = await pluginBridge.send({ type: 'ssh-sessions' });
// r = { type: 'sessions', data: [{ sessionId, host, username, port, connected }] }
const sessions = r.data;
```

### `sftp-list` — List remote directory

```js
const r = await pluginBridge.send({
  type: 'sftp-list',
  sessionId: 's1',
  path: '/var/log'
});
// r = { type: 'sftp-entries', data: [{ name, isDir, size, modified }] }
// OR { type: 'error', message: '...' }
```

### `sftp-read` — Read remote file content

```js
const r = await pluginBridge.send({
  type: 'sftp-read',
  sessionId: 's1',
  path: '/etc/hostname'
});
// r = { type: 'sftp-content', content: '...' }
```

> **Note:** Native message types do **not** need to be declared in `plugin.json` permissions — they are handled by Dart, not the JS bridge. The plugin still needs `session.observe` to track session IDs.

---

## 7. Lifecycle & hot-reload

### Load sequence

```
App start
  │
  ├── Scan ~/.yourssh/plugins/
  ├── Validate plugin.json
  ├── Check permissions (show consent dialog if not yet approved)
  └── Execute index.js → plugin.on(...) registers handlers
```

### Hot-reload

The app watches for file changes. When a `.js` or `plugin.json` file changes:
1. Unloads the old plugin (clears all handlers)
2. Reloads and re-executes from scratch

**No app restart needed.** Just save the file and the plugin reloads immediately.

### No state persistence across reloads

Top-level `var myState = {}` resets on plugin reload. Use `storage.set/get` to persist data across sessions and reloads.

---

## 8. Security & permissions

### When installing a plugin

The app shows a consent dialog listing all requested permissions. The user approves or denies each one. Plugins can only call bridge functions for permissions the user has approved.

### Permission reference

| Permission | Grants access to |
|-----------|-----------------|
| `terminal.read` | Observe `terminal.output` and `terminal.input` (read-only, return value ignored) |
| `terminal.transform` | Modify terminal output data |
| `terminal.intercept` | Cancel or modify user keystrokes before they reach SSH |
| `session.observe` | Receive `session.connect` / `session.disconnect` events |
| `session.control` | `session.connect.before` — can cancel a connection |
| `ssh.exec` | Call `ssh.exec()` to run commands on remote |
| `terminal.inject` | Send text directly into an active shell via `ssh.inject()` |
| `sftp.read` | `sftp.list()`, `sftp.read()` |
| `sftp.write` | `sftp.write()`, `sftp.delete()`, `sftp.mkdir()` |
| `command.intercept` | `command.before` / `command.after` hooks for SSH exec commands |
| `ui.notify` | Show desktop notifications |
| `ui.statusbar` | Add items to the status bar |
| `ui.clipboard` | Write to the system clipboard |
| `ui.panel` | Register a sidebar panel with WebView UI |

### Principle of least privilege

Only request permissions that are actually needed. For example, a log highlighter plugin only needs `terminal.transform` — it does not need `ssh.exec` or `sftp.write`.

---

## 9. Examples

### Example 1: Log Highlighter

Highlights ERROR/WARN/INFO levels in terminal output.

**plugin.json:**
```json
{
  "id": "dev.example.log-highlighter",
  "name": "Log Highlighter",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.transform"]
}
```

**index.js:**
```js
plugin.on("terminal.output", function(ctx) {
  var data = ctx.data;
  data = data.replace(/\bERROR\b/g, "\x1b[31;1mERROR\x1b[0m");
  data = data.replace(/\bWARN\b/g,  "\x1b[33;1mWARN\x1b[0m");
  data = data.replace(/\bINFO\b/g,  "\x1b[36mINFO\x1b[0m");
  return data;
});
```

---

### Example 2: CPU Monitor

Shows remote server CPU usage in the status bar, updated every 10 seconds via panel HTML.

**plugin.json:**
```json
{
  "id": "dev.example.cpu-monitor",
  "name": "CPU Monitor",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["session.observe", "ui.statusbar", "ui.panel"]
}
```

**index.js:**
```js
plugin.on("session.connect", function(ctx) {
  ui.statusbar.add("cpu-" + ctx.sessionId, {
    label: "CPU: --",
    tooltip: ctx.host + " CPU usage"
  });
});

plugin.on("session.disconnect", function(ctx) {
  ui.statusbar.remove("cpu-" + ctx.sessionId);
});

ui.panel.register({
  title: "CPU Monitor",
  icon: "monitor",
  webviewEntry: "panel/index.html",
  onMessage: function(msg) { return { type: "ok" }; }
});
```

**panel/index.html** (simplified — poll via native message):
```js
async function poll() {
  const sessions = (await pluginBridge.send({ type: 'ssh-sessions' })).data;
  if (!sessions.length) return;
  const r = await pluginBridge.send({
    type: 'ssh-exec',
    sessionId: sessions[0].sessionId,
    command: "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"
  });
  document.getElementById('cpu').textContent = 'CPU: ' + r.stdout.trim() + '%';
}
setInterval(poll, 10000);
poll();
```

---

### Example 3: Auto-run on connect

Automatically runs commands after connecting to a specific host.

**plugin.json:**
```json
{
  "id": "dev.example.auto-run",
  "name": "Auto Run",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["session.observe", "terminal.inject"]
}
```

**index.js:**
```js
var AUTO_COMMANDS = {
  "prod-server.com": [
    "cd /var/app && git log --oneline -5\n",
    "systemctl status myapp --no-pager\n"
  ]
};

plugin.on("session.connect", function(ctx) {
  var cmds = AUTO_COMMANDS[ctx.host];
  if (!cmds) return;
  for (var i = 0; i < cmds.length; i++) {
    ssh.inject(ctx.sessionId, cmds[i]);
  }
});
```

---

### Example 4: Block dangerous commands

Blocks dangerous patterns before the user submits them.

**plugin.json:**
```json
{
  "id": "dev.example.safety-guard",
  "name": "Safety Guard",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["command.intercept", "ui.notify"]
}
```

**index.js:**
```js
var BLOCKED = [/rm\s+-rf\s+\//, /dd\s+if=\/dev\/zero\s+of=\/dev\//, /mkfs\./];

plugin.on("command.before", function(ctx) {
  for (var i = 0; i < BLOCKED.length; i++) {
    if (BLOCKED[i].test(ctx.command)) {
      ui.notify("Command blocked by Safety Guard", { type: "warning" });
      return false; // cancel
    }
  }
  return ctx.command;
});
```

---

### Example 5: Persistent notes per host

Saves per-host notes using the storage API and a WebView panel.

**plugin.json:**
```json
{
  "id": "dev.example.host-notes",
  "name": "Host Notes",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["session.observe", "ui.panel"]
}
```

**index.js:**
```js
ui.panel.register({
  title: "Host Notes",
  icon: "note",
  webviewEntry: "panel/index.html",
  onMessage: function(msg) {
    if (msg.type === "save-note") {
      storage.set("note-" + msg.host, msg.content);
      return { type: "saved" };
    }
    if (msg.type === "load-note") {
      var result = storage.get("note-" + msg.host);
      return { type: "note", content: result ? result.value : "" };
    }
  }
});
```

---

## 10. Debugging

### Plugin Console

**Settings → Script Plugins → [plugin name] → Console**

All `console.log()` and `console.error()` output from the plugin appears here. JS runtime errors are also logged.

### Circuit breaker

If a plugin throws an exception 5 or more times, the app shows a warning. At 10 exceptions, the plugin is automatically disabled.

To re-enable: go to Plugin Manager and save the file (hot-reload resets the error count).

### Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Plugin "x" does not have permission: ssh.exec` | Missing permission in manifest | Add it to the `permissions` array |
| `ManifestException: plugin.json missing required field: name` | Missing required field | Add the field to plugin.json |
| `QuickJsException: SyntaxError` | JS syntax error | Fix index.js |
| Plugin does not load | plugin.json cannot be parsed | Validate JSON at jsonlint.com |

### Testing a plugin locally

```bash
# Create plugin directory
mkdir -p ~/.yourssh/plugins/test-plugin

# Write manifest
cat > ~/.yourssh/plugins/test-plugin/plugin.json << 'EOF'
{
  "id": "dev.local.test",
  "name": "Test",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.transform"]
}
EOF

# Write plugin
cat > ~/.yourssh/plugins/test-plugin/index.js << 'EOF'
plugin.on("terminal.output", function(ctx) {
  console.log("Got data: " + ctx.data.length + " bytes");
  return ctx.data;
});
EOF

# Open app → consent dialog appears
# After approving, edit index.js → plugin reloads automatically
```

---

## 11. Known limitations

| Limitation | Workaround |
|-----------|------------|
| `ssh.exec()` does not work inside JS hook handlers (`session.connect`, `terminal.output`, etc.) — the JS runtime is synchronous | Use the **native panel message** `ssh-exec` from panel HTML instead |
| `setInterval` / `setTimeout` are not available in the JS plugin context | Use `session.connect` hook to trigger logic; timer-based polling must run from panel HTML (the browser has native timers) |
| `ui.addCommand` click handler is not invoked — commands appear in the palette but clicking them is a no-op | Known limitation — will be fixed in a future release |
| `sftp.write`, `sftp.delete`, `sftp.mkdir` in JS are not yet implemented | Use `ssh.inject(sessionId, "rm file\n")` to perform operations via the SSH shell |
| Plugin panel WebView loads from `file://` — some browser security policies may block `fetch()` | Use native panel messages (`ssh-exec`, `sftp-read`) instead of `fetch()` in panel HTML |
| Plugins cannot share state with each other | Use `storage.set/get` with a shared key prefix (there is no read-isolation between plugins) |

---

## 12. Pre-publish checklist

- [ ] ID follows reverse-domain format (`dev.yourname.pluginname`)
- [ ] Only request permissions that are actually needed (least privilege)
- [ ] `terminal.output` / `terminal.input` handlers are synchronous and fast
- [ ] Async operations use native panel messages, not JS hook handlers
- [ ] Persistent state uses `storage` (not JS variables)
- [ ] Cleanup in `session.disconnect` if the plugin added statusbar items or timers
- [ ] Tested with 0 active sessions (handlers do not crash when `ssh.sessions()` returns empty)
- [ ] `console.log` debug lines removed or reduced before publishing
- [ ] `plugin.json` is valid JSON
- [ ] `README.md` in the plugin folder describes what the plugin does

---

## Plugin directory reference

```
~/.yourssh/plugins/
  my-plugin/
    plugin.json          ← required: manifest
    index.js             ← required: entry point
    README.md            ← optional but recommended
    lib/
      utils.js           ← optional helper modules
    panel/
      index.html         ← optional WebView UI for ui.panel
```
