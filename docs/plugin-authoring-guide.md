# YourSSH Plugin Authoring Guide

Hướng dẫn viết script plugin cho YourSSH từ A đến Z — không cần rebuild app, chỉ cần tạo thư mục và viết JS.

---

## Mục lục

1. [Cách hoạt động](#1-cách-hoạt-động)
2. [Cấu trúc plugin](#2-cấu-trúc-plugin)
3. [Manifest (plugin.json)](#3-manifest-pluginjson)
4. [API: Hook events](#4-api-hook-events)
5. [API: Bridge functions](#5-api-bridge-functions)
6. [API: Native panel messages](#6-api-native-panel-messages)
7. [Lifecycle & hot-reload](#7-lifecycle--hot-reload)
8. [Security & permissions](#8-security--permissions)
9. [Ví dụ thực tế](#9-ví-dụ-thực-tế)
10. [Debugging](#10-debugging)
11. [Known limitations](#11-known-limitations)
12. [Checklist trước khi publish](#12-checklist-trước-khi-publish)

---

## 1. Cách hoạt động

YourSSH chạy mỗi plugin trong một **JavaScript runtime riêng biệt** (QuickJS). Khi app khởi động, nó scan thư mục `~/.yourssh/plugins/`, load từng plugin, và inject một đối tượng `plugin` vào JS context.

Plugin đăng ký handler thông qua `plugin.on(event, handler)`. App fire các event này tại đúng thời điểm (khi có data từ SSH, khi session connect, v.v.) — handler của plugin được gọi synchronously hoặc asynchronously tùy event.

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

## 2. Cấu trúc plugin

```
~/.yourssh/plugins/
  my-plugin/
    plugin.json     ← bắt buộc: manifest
    index.js        ← bắt buộc: entry point
    lib/
      helpers.js    ← tùy chọn: file phụ
```

Plugin là một **thư mục** trong `~/.yourssh/plugins/`. App nhận diện plugin qua `plugin.json`. Không cần install, không cần build.

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

### Các trường bắt buộc

| Field | Mô tả |
|-------|-------|
| `id` | Reverse-domain ID duy nhất. Pattern: `^[a-z0-9][a-z0-9._\-]{0,63}$` |
| `name` | Tên hiển thị trong UI |
| `version` | Semantic version: `MAJOR.MINOR.PATCH` |
| `entry` | File JS entry point (relative to plugin folder) |
| `minAppVersion` | Version YourSSH tối thiểu |
| `permissions` | Danh sách quyền cần (xem mục 7) |

### ID format

- Phải bắt đầu bằng chữ thường hoặc số
- Chỉ dùng: `a-z`, `0-9`, `.`, `_`, `-`
- Tối đa 64 ký tự
- Nên theo reverse-domain: `dev.yourname.pluginname`

---

## 4. API: Hook events

Plugin đăng ký handler qua `plugin.on(event, handler)`.

### Terminal events

#### `terminal.output` — Transform terminal output

> **Required permission:** `terminal.transform` (để modify) hoặc `terminal.read` (để observe-only)

```js
plugin.on("terminal.output", function(ctx) {
  // ctx.sessionId : string — ID của SSH session
  // ctx.data      : string — raw terminal output text (có thể có ANSI escape codes)

  // Return string → replace data
  // Return null / undefined → pass-through (không thay đổi)
  return ctx.data.replace(/ERROR/g, "\x1b[31mERROR\x1b[0m");
});
```

**Hot path:** Handler này được gọi với mỗi chunk data từ SSH server. Phải **synchronous** và **nhanh** (< 5ms). Đừng làm I/O hoặc tính toán nặng ở đây.

---

#### `terminal.input` — Intercept user keystrokes

> **Required permission:** `terminal.intercept`

```js
plugin.on("terminal.input", function(ctx) {
  // ctx.sessionId : string
  // ctx.data      : string — keystroke(s) sắp được gửi lên SSH server

  // Return false → cancel (keystroke không được gửi)
  // Return string → modify và gửi string đó
  // Return null / undefined → pass-through

  if (ctx.data.trim() === "rm -rf /") return false; // block
  return ctx.data; // pass-through
});
```

**Hot path:** Phải synchronous.

---

### Session events

#### `session.connect` — Session đã connect thành công

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

Async được phép (handler không block terminal).

---

#### `session.disconnect` — Session đóng

> **Required permission:** `session.observe`

```js
plugin.on("session.disconnect", function(ctx) {
  // ctx.sessionId : string
  ui.statusbar.remove("my-status-" + ctx.sessionId);
});
```

---

#### `session.connect.before` — Trước khi connect (có thể cancel)

> **Required permission:** `session.control`

```js
plugin.on("session.connect.before", function(ctx) {
  if (ctx.host === "blocked-host.com") return false; // cancel connect
  // return nothing → allow
});
```

---

### Command events

#### `command.before` — Trước khi chạy `ssh.exec()`

> **Required permission:** `command.intercept`

```js
plugin.on("command.before", async function(ctx) {
  // ctx.sessionId : string
  // ctx.command   : string — lệnh sắp chạy

  // Return false → cancel
  // Return string → replace command
  console.log("Running: " + ctx.command);
  return ctx.command;
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

#### `command.after` — Sau khi `ssh.exec()` hoàn thành

> **Required permission:** `command.intercept`

```js
plugin.on("command.after", function(ctx) {
  // ctx.sessionId : string
  // ctx.command   : string — lệnh đã chạy
  // ctx.stdout    : string
  // ctx.stderr    : string
  // ctx.exitCode  : number
  if (ctx.exitCode !== 0) {
    console.error("[plugin] Command failed: " + ctx.command);
  }
});
```

---

## 5. API: Bridge functions

Bridge functions cho phép plugin gọi vào app. Chỉ available nếu có permission tương ứng.

### `ssh` — SSH operations

#### `ssh.sessions()` → `Array`

> **Permission:** `session.observe` hoặc `ssh.exec`

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

#### `ssh.exec(sessionId, command)` → `Promise<Object>`

> **Permission:** `ssh.exec`

```js
plugin.on("session.connect", async function(ctx) {
  const result = await ssh.exec(ctx.sessionId, "uname -a");
  console.log(result.stdout);  // string
  console.log(result.stderr);  // string
  console.log(result.exitCode); // number
});
```

---

### `sftp` — File operations

> **Permission:** `sftp.read` (cho list/read) hoặc `sftp.write` (cho write/delete/mkdir)

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

> **Permission:** Không cần — luôn available. Tự động namespace theo plugin id.

```js
// Save
await storage.set("mykey", "myvalue");

// Load
const val = await storage.get("mykey");
if (val !== null) console.log(val.value);

// Delete
await storage.delete("mykey");
```

Keys được namespace tự động: `plugin::<id>::storage::<key>` — không cần lo về conflict với plugin khác.

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

Status bar item xuất hiện ở bottom của app window.

#### `ui.panel.register(config)` — Sidebar panel (WebView)

> **Permission:** `ui.panel`

```js
ui.panel.register({
  title: "My Panel",
  icon: "monitor",
  webviewEntry: "panel/index.html",  // relative to plugin folder
  onMessage: async function(msg) {
    if (msg.type === "fetch-stats") {
      const sessions = ssh.sessions();
      const r = await ssh.exec(sessions[0].sessionId, "df -h");
      return { type: "stats", data: r.stdout };
    }
  }
});
```

Panel HTML có thể gọi Dart bridge qua `window.pluginBridge.sendMessage(msg)`.

---

### `console` — Debug logging

> **Permission:** Không cần — luôn available.

```js
console.log("debug message");
console.warn("warning");
console.error("error message");
```

Logs hiện trong **Plugin Console** (Settings → Script Plugins → plugin → Console). Hỗ trợ nhiều arguments:

```js
console.log("Sessions:", sessions.length, "connected");
```

### `ui.addCommand` — Register command palette entry

> **Permission:** `ui.statusbar` hoặc `ui.panel`

```js
ui.addCommand({
  id: "clear-logs",
  label: "Clear Remote Logs",
  keybinding: "Ctrl+Shift+L"  // optional
});
```

Command sẽ xuất hiện trong command palette. **Lưu ý:** Hiện tại command chỉ xuất hiện trong UI — callback chưa được implement (known limitation).

---

## 6. API: Native panel messages

Plugin panel HTML có thể gửi **native messages** để thực hiện SSH/SFTP operations mà không cần JS async. Dart xử lý trực tiếp và trả kết quả về WebView.

Sử dụng trong panel HTML qua `pluginBridge.send()`:

### `ssh-exec` — Run SSH command

```js
// In panel/index.html
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

> **Note:** Các native message type trên **không cần declare trong `plugin.json` permissions** vì chúng được xử lý bởi Dart, không phải JS bridge. Tuy nhiên plugin vẫn cần `session.observe` để track sessionId.

---

---

## 7. Lifecycle & hot-reload

### Load sequence

```
App start
  │
  ├── Scan ~/.yourssh/plugins/
  ├── Validate plugin.json
  ├── Check permissions (prompt user nếu chưa approve)
  └── Execute index.js → plugin.on(...) registers handlers
```

### Hot-reload

App watch file changes. Khi `.js` hoặc `plugin.json` thay đổi:
1. Unload plugin cũ (clear tất cả handlers)
2. Reload và execute lại từ đầu

**Không cần restart app để test.** Chỉ cần save file, plugin reload ngay.

### Không có state persistence qua reload

`var myState = {}` ở top-level sẽ reset khi plugin reload. Dùng `storage.set/get` để persist data qua sessions và reloads.

---

## 8. Security & permissions

### Khi install plugin

App hiện dialog để user approve/deny từng permission. Plugin chỉ có thể gọi bridge functions mà user đã approve.

### Permission reference

| Permission | Cho phép |
|-----------|---------|
| `terminal.read` | Observe `terminal.output` và `terminal.input` (read-only, return value ignored) |
| `terminal.transform` | Modify terminal output data |
| `terminal.intercept` | Cancel/modify user keystrokes trước khi gửi SSH |
| `session.observe` | Nhận `session.connect` / `session.disconnect` events |
| `session.control` | `session.connect.before` — có thể cancel connect |
| `ssh.exec` | Gọi `ssh.exec()` để chạy lệnh trên remote |
| `sftp.read` | `sftp.list()`, `sftp.read()` |
| `sftp.write` | `sftp.write()`, `sftp.delete()`, `sftp.mkdir()` |
| `command.intercept` | `command.before` — modify/cancel SSH exec commands |
| `ui.notify` | Hiện desktop notification |
| `ui.statusbar` | Thêm items vào status bar |
| `ui.panel` | Đăng ký sidebar panel với WebView UI |

### Nguyên tắc least privilege

Chỉ request những permissions thực sự cần. Ví dụ: nếu plugin chỉ highlight log output, chỉ cần `terminal.transform` — không cần `ssh.exec` hay `sftp.write`.

---

## 9. Ví dụ thực tế

### Example 1: Log Highlighter

Highlight ERROR/WARN/INFO trong terminal output.

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

Hiển thị CPU usage của remote server trong status bar, cập nhật mỗi 10 giây.

**plugin.json:**
```json
{
  "id": "dev.example.cpu-monitor",
  "name": "CPU Monitor",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["session.observe", "ssh.exec", "ui.statusbar"]
}
```

**index.js:**
```js
var _timers = {};

plugin.on("session.connect", async function(ctx) {
  var sessionId = ctx.sessionId;
  var itemId = "cpu-" + sessionId;

  ui.statusbar.add(itemId, {
    label: "CPU: ...",
    tooltip: ctx.host + " CPU usage"
  });

  async function refresh() {
    try {
      var r = await ssh.exec(sessionId, "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'");
      var pct = r.stdout.trim();
      ui.statusbar.update(itemId, { label: "CPU: " + pct + "%" });
    } catch (e) {
      // session may have closed
    }
  }

  await refresh();
  _timers[sessionId] = setInterval(refresh, 10000);
});

plugin.on("session.disconnect", function(ctx) {
  var sessionId = ctx.sessionId;
  if (_timers[sessionId]) {
    clearInterval(_timers[sessionId]);
    delete _timers[sessionId];
  }
  ui.statusbar.remove("cpu-" + sessionId);
});
```

---

### Example 3: Auto-run on connect

Tự động chạy một số lệnh sau khi connect vào host cụ thể.

**plugin.json:**
```json
{
  "id": "dev.example.auto-run",
  "name": "Auto Run",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["session.observe", "ssh.exec"]
}
```

**index.js:**
```js
var AUTO_COMMANDS = {
  "prod-server.com": [
    "cd /var/app && git log --oneline -5",
    "systemctl status myapp --no-pager"
  ]
};

plugin.on("session.connect", async function(ctx) {
  var cmds = AUTO_COMMANDS[ctx.host];
  if (!cmds) return;

  for (var i = 0; i < cmds.length; i++) {
    var r = await ssh.exec(ctx.sessionId, cmds[i]);
    console.log("[auto-run] " + cmds[i] + ":\n" + r.stdout);
  }
});
```

---

### Example 4: Block dangerous commands

Chặn các lệnh nguy hiểm trước khi user gõ Enter.

**plugin.json:**
```json
{
  "id": "dev.example.safety-guard",
  "name": "Safety Guard",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["terminal.intercept", "ui.notify"]
}
```

**index.js:**
```js
var BLOCKED_PATTERNS = [
  /rm\s+-rf\s+\//,
  /dd\s+if=\/dev\/zero\s+of=\/dev\//,
  /mkfs\./
];

plugin.on("terminal.input", function(ctx) {
  var input = ctx.data;

  // Only check on Enter
  if (input !== "\r" && input !== "\n") return input;

  // We don't have buffer access here — this is a simplified approach
  // For production, maintain a per-session input buffer
  for (var i = 0; i < BLOCKED_PATTERNS.length; i++) {
    if (BLOCKED_PATTERNS[i].test(input)) {
      ui.notify("Command blocked by Safety Guard plugin", { type: "warning" });
      return false; // cancel
    }
  }
  return input;
});
```

---

### Example 5: Persistent notes per host

Lưu notes cho từng host, dùng storage API.

**plugin.json:**
```json
{
  "id": "dev.example.host-notes",
  "name": "Host Notes",
  "version": "1.0.0",
  "entry": "index.js",
  "minAppVersion": "1.0.0",
  "permissions": ["session.observe", "ssh.exec", "ui.panel"]
}
```

**index.js:**
```js
ui.panel.register({
  title: "Host Notes",
  icon: "note",
  webviewEntry: "panel/index.html",
  onMessage: async function(msg) {
    if (msg.type === "save-note") {
      await storage.set("note-" + msg.host, msg.content);
      return { type: "saved" };
    }
    if (msg.type === "load-note") {
      var result = await storage.get("note-" + msg.host);
      return { type: "note", content: result ? result.value : "" };
    }
  }
});
```

---

## 10. Debugging

### Plugin Console

**Settings → Script Plugins → [plugin name] → Console**

Mọi `console.log()` và `console.error()` trong plugin hiện ở đây. Lỗi JS runtime cũng được log.

### Circuit breaker

Nếu plugin throw exception >= 5 lần, app hiện warning. Đến 10 lần, plugin tự động disabled.

Để re-enable: vào Plugin Manager, restart plugin hoặc sửa file (hot-reload sẽ reset error count).

### Common errors

| Error | Nguyên nhân | Fix |
|-------|------------|-----|
| `Plugin "x" does not have permission: ssh.exec` | Missing permission in manifest | Thêm vào `permissions` array |
| `ManifestException: plugin.json missing required field: name` | Thiếu field | Thêm field vào plugin.json |
| `QuickJsException: SyntaxError` | Lỗi cú pháp JS | Sửa index.js |
| Plugin không load | plugin.json không parse được | Validate JSON tại jsonlint.com |

### Testing plugin locally

```bash
# Tạo plugin thư mục
mkdir -p ~/.yourssh/plugins/test-plugin

# Viết manifest
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

# Viết plugin
cat > ~/.yourssh/plugins/test-plugin/index.js << 'EOF'
plugin.on("terminal.output", function(ctx) {
  console.log("Got data: " + ctx.data.length + " bytes");
  return ctx.data;
});
EOF

# Mở app → consent dialog sẽ xuất hiện
# Sau khi approve, sửa index.js → plugin tự reload
```

---

## 11. Known limitations

| Limitation | Workaround |
|-----------|------------|
| `ssh.exec(sessionId, cmd)` không hoạt động trong JS hook handlers (`session.connect`, `terminal.output`, v.v.) — JS runtime là synchronous | Dùng **native panel message** `ssh-exec` từ panel HTML thay thế |
| `setInterval` / `setTimeout` chưa available trong JS plugin context | Dùng `session.connect` hook để kick off logic; timer-based polling phải từ panel HTML (browser có native timers) |
| `ui.addCommand` handler chưa được invoke khi user click — command chỉ xuất hiện trong palette | Known limitation — sẽ được fix trong phiên bản tới |
| `sftp.write`, `sftp.delete`, `sftp.mkdir` trong JS chưa implement | Dùng `ssh.inject(sessionId, "rm file\n")` để thực hiện qua SSH shell |
| Plugin panel WebView load từ `file://` — một số browser security policies có thể chặn `fetch()` | Dùng native panel messages (`ssh-exec`, `sftp-read`) thay vì `fetch()` trong panel HTML |
| Plugin không thể share state với nhau | Dùng `storage.set/get` với cùng một key prefix (không có namespace isolation giữa các plugin về read) |

## 12. Checklist trước khi publish

- [ ] ID theo reverse-domain format (`dev.yourname.pluginname`)
- [ ] Chỉ request permissions thực sự cần (least privilege)
- [ ] `terminal.output` / `terminal.input` handlers là synchronous và nhẹ
- [ ] Async operations (ssh.exec, sftp.*) chỉ trong non-hot-path handlers
- [ ] State được lưu trong `storage` (không phải JS variable) nếu cần persist
- [ ] Cleanup trong `session.disconnect` nếu plugin tạo setInterval hoặc statusbar items
- [ ] Test với 0 active sessions (plugin.on handlers không crash khi `ssh.sessions()` rỗng)
- [ ] `console.log` debug lines được remove hoặc giảm trước khi publish
- [ ] `plugin.json` validate được (không lỗi JSON)
- [ ] README.md trong plugin folder mô tả plugin làm gì

---

## Plugin directory reference

```
~/.yourssh/plugins/
  my-plugin/
    plugin.json          ← manifest (bắt buộc)
    index.js             ← entry point (bắt buộc)
    README.md            ← tùy chọn nhưng nên có
    lib/
      utils.js           ← helper modules (tùy chọn)
    panel/
      index.html         ← WebView UI nếu dùng ui.panel (tùy chọn)
```

> **Tip:** Dùng `/schedule` trong Claude Code để tự động nhắc bạn update plugin version sau mỗi major change.
