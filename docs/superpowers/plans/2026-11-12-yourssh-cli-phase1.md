# YourSSH CLI — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `yourssh connect <host>`, `yourssh ls [--json]`, `yourssh version` and `yourssh://connect/<host>` drive the running desktop app through an authenticated local IPC endpoint, with single-instance forwarding.

**Architecture:** A pure-Dart package `packages/yourssh_cli` holds the wire protocol, endpoint/token helpers and the `yourssh` executable. The app embeds a `CliServer` (transport-agnostic request handler) behind a Unix-socket listener (macOS/Linux) or a named-pipe listener (Windows), started after the main window is up; a second app launch or a URL activation forwards its request to the running instance and exits.

**Tech Stack:** Dart 3 (CI Flutter 3.47.1), `package:args`, `dart:io` Unix sockets + `Socket.getRawOption` for peer credentials, `dart:ffi` (`getuid`) and `package:win32` for Windows pipes, Swift (macOS URL events), Inno Setup / `.desktop` for URL registration.

**Spec:** `docs/superpowers/specs/2026-11-12-yourssh-cli-design.md`

## Global Constraints

- CI builds with Flutter **3.47.1** — no newer APIs.
- `packages/yourssh_cli` must not import Flutter; the app depends on it by path for the protocol.
- Secrets never appear on argv, in env vars, in URLs, in CLI output or in `--json` (spec anti-goal).
- IPC endpoint: macOS `~/Library/Application Support/YourSSH/run/cli.sock`; Linux `$XDG_RUNTIME_DIR/yourssh/cli.sock` (fallback `~/.local/state/yourssh/run/cli.sock`); Windows `\\.\pipe\yourssh-cli-<user SID>`. Run dir 0700, socket and token file 0600; peer uid must equal the app's uid; Windows DACL = current user SID only + `PIPE_REJECT_REMOTE_CLIENTS`.
- Token: 32 random bytes, lowercase hex, file `cli.token` in the run dir, rewritten on every app start; compared in constant time.
- Protocol v1: one newline-terminated JSON request per connection, one JSON response line, then close. Request `{"v":1,"id","token","cmd","args"}`; response `{"v":1,"id","ok":true,"result"}` or `{"v":1,"id","ok":false,"code","error"[,"candidates"]}`. Unknown fields rejected. Max request line 64 KiB.
- Exit codes: 0 success · 1 runtime error · 2 usage/ambiguous host · 3 app not reachable / protocol mismatch · 4 denied by the app.
- When the app isn't running the CLI launches it and waits up to **15 s** for socket + token.
- `yourssh://` URLs open **saved hosts only**; no ad-hoc hosts, commands, tunnels or imports from URLs.
- Every state-changing CLI/URL action is audited with `meta.source` = `cli` / `url`.

## Review Focus

- **Stale socket after a crash** — a leftover `cli.sock` must not block the next app start (unlink + rebind), and the CLI must treat "connection refused" as "app not running" (launch it), not as an error. → Task 4 tests.
- **Two app launches at the same time** — exactly one binds the endpoint; the other forwards its request and exits 0. → Task 6 test.
- **Hostile or broken request lines** — invalid JSON, missing/wrong token, wrong `v`, unknown `cmd`, a 10 MB line: rejected with an error response (or connection closed), the server keeps serving. → Task 3 tests.
- **Host labels with spaces, accents or mixed case** — `connect "Prod DB"` matches label `prod db` exactly (case-insensitive, NFC), two matches → exit 2 listing both. → Task 2 tests.
- **Crafted URLs** — `yourssh://connect/..%2F..`, `yourssh://exec/x`, `yourssh://connect/` (empty), unknown host, ad-hoc `user@host` in a URL: all rejected, nothing connects. → Task 3 tests.

---

### Task 1: Protocol and endpoint package

**Files:**
- Create: `packages/yourssh_cli/pubspec.yaml` (pure Dart, deps: `args`, `path`; dev: `test`)
- Create: `packages/yourssh_cli/lib/protocol.dart`, `packages/yourssh_cli/lib/endpoint.dart`, `packages/yourssh_cli/lib/yourssh_cli.dart` (exports)
- Test: `packages/yourssh_cli/test/protocol_test.dart`, `packages/yourssh_cli/test/endpoint_test.dart`

**Interfaces:**
- Produces:
  - `const int kCliProtocolVersion = 1;` `const int kMaxRequestBytes = 64 * 1024;`
  - `enum CliExit { ok(0), runtime(1), usage(2), unreachable(3), denied(4) }` with `final int code`
  - `class CliRequest { final String id, token, cmd; final Map<String, Object?> args; String encode(); static CliRequest decode(String line); }` — `decode` throws `CliProtocolException(CliExit code, String message)` on invalid JSON, wrong `v`, missing/extra fields, line > `kMaxRequestBytes`.
  - `class CliResponse { final String id; final bool ok; final Object? result; final CliExit? code; final String? error; final List<Map<String, Object?>>? candidates; String encode(); static CliResponse decode(String line); factory CliResponse.success(String id, Object? result); factory CliResponse.failure(String id, CliExit code, String error, {List<Map<String, Object?>>? candidates}); }`
  - `const Set<String> kCliCommands = {'connect', 'ls', 'version', 'open'};` and `void validateArgs(String cmd, Map<String, Object?> args)` (throws `CliProtocolException(usage)`): `connect {host: String}`, `ls {tag: String?, filter: String?}`, `version {}`, `open {url: String}`.
  - `class CliEndpoint { final String runDir; final String address; final String tokenPath; static CliEndpoint resolve({required String os, required Map<String, String> env, required String home, String? userSid}); }` — `address` is the socket path (POSIX) or pipe name (Windows).
  - `Future<String> writeToken(String runDir)` (creates dir 0700 + file 0600 on POSIX, returns hex) and `Future<String?> readToken(String tokenPath)`; `bool tokensEqual(String a, String b)` (constant time).

- [ ] **Step 1: Write failing tests** — `protocol_test.dart`: round-trip encode/decode for each command; `decode('{')` throws usage; `v: 2` throws unreachable; extra field `"x":1` throws usage; a 70 KiB line throws usage; `validateArgs('connect', {})` throws; `validateArgs('rm', {})` throws. `endpoint_test.dart`: `resolve(os:'macos', home:'/Users/a')` → `/Users/a/Library/Application Support/YourSSH/run/cli.sock`; linux with `XDG_RUNTIME_DIR=/run/user/501` → `/run/user/501/yourssh/cli.sock`, without it → `/home/a/.local/state/yourssh/run/cli.sock`; windows with SID `S-1-5-21-1` → `\\.\pipe\yourssh-cli-S-1-5-21-1`; `writeToken` in a temp dir → 64 hex chars, dir mode `0700`, file mode `0600` (skip mode checks on Windows); `tokensEqual('ab','ab')` true, `('ab','ac')` false, different lengths false.
- [ ] **Step 2: Run** `cd packages/yourssh_cli && dart pub get && dart test` — Expected: FAIL (missing libraries).
- [ ] **Step 3: Implement** `protocol.dart` and `endpoint.dart` per the interfaces (token from `Random.secure()`; chmod via `Process.run('chmod', …)` or `File.setPermissions`-equivalent available on Dart 3.12 — create the file empty, restrict, then write).
- [ ] **Step 4: Run** `dart test` — Expected: all pass. Add the package to `.github/workflows/pr-test.yml` as a `dart test` step in the `app` job's matrix or a new lightweight job.
- [ ] **Step 5: Commit** `feat(cli): wire protocol, endpoint paths and token file`

### Task 2: Host resolution and secret-free host summaries

**Files:**
- Create: `app/lib/services/cli/host_resolver.dart`, `app/lib/services/cli/host_summary.dart`
- Test: `app/test/services/cli/host_resolver_test.dart`, `app/test/services/cli/host_summary_test.dart`

**Interfaces:**
- Consumes: `Host` (`app/lib/models/host.dart`), `HostProvider.hosts`.
- Produces:
  - `sealed class HostResolution` with `ResolvedHost(Host host)`, `AmbiguousHost(List<Host> candidates)`, `AdHocTarget(String user, String hostname, int port)`, `UnknownHost(String query)`.
  - `HostResolution resolveHost(String query, List<Host> hosts, {required bool allowAdHoc})` — order: exact id → label (case-insensitive, NFC-normalized, trimmed) → `user@hostname[:port]` matching a saved host → `AdHocTarget` only when `allowAdHoc` → `UnknownHost`.
  - `Map<String, Object?> hostSummary(Host h)` — keys exactly: `id, label, username, host, port, protocol, tags, jumpHostIds`.

- [ ] **Step 1: Write failing tests** — id match wins over a label equal to another host's id; `"Prod DB"` matches label `prod db`; NFD `"Kết nối"` matches NFC label; two labels `web` → `AmbiguousHost` with both; `root@10.0.0.5:2222` matches the saved host with those fields; same string with no saved match → `AdHocTarget('root','10.0.0.5',2222)` when allowed, `UnknownHost` when not; `hostSummary` of a host with a password/keyId/envVars/startupSnippet contains none of those keys and exactly the 8 listed keys.
- [ ] **Step 2: Run** `cd app && flutter test test/services/cli/` — Expected: FAIL.
- [ ] **Step 3: Implement** both files (NFC via the `unorm_dart` dependency already used by the xterm fork, or `package:characters` if that is what the app already depends on — check `app/pubspec.yaml`).
- [ ] **Step 4: Run** the same command — Expected: PASS.
- [ ] **Step 5: Commit** `feat(cli): host resolution and secret-free host summaries`

### Task 3: `CliServer` request handling

**Files:**
- Create: `app/lib/services/cli/cli_server.dart`, `app/lib/services/cli/cli_handlers.dart`
- Test: `app/test/services/cli/cli_server_test.dart`

**Interfaces:**
- Consumes: Task 1 protocol, Task 2 resolver/summary, `AuditService.record(AuditEvent)`.
- Produces:
  - `abstract class CliHandlers { List<Host> get hosts; Future<void> connect(Host host, {required String source}); Future<void> connectAdHoc(AdHocTarget target); Future<void> focusWindow(); String get appVersion; }`
  - `class CliServer { CliServer({required CliHandlers handlers, required String token, AuditService? audit}); Future<String> handleLine(String line, {required bool trusted, String source = 'cli'}); }` — `trusted: true` skips the token check (in-process URL events); returns one encoded `CliResponse`.
  - Results: `connect` → `{"host": hostSummary}`; `ls` → `{"hosts": [hostSummary…]}` filtered by `tag`/`filter` (substring of label/host, case-insensitive); `version` → `{"app": appVersion, "protocol": 1}`; `open` → parses `yourssh://connect/<id-or-label>` (percent-decoded once, must be a single path segment, no `/`), resolves with `allowAdHoc: false`, then behaves like `connect` with `source: 'url'`.
  - Audit: `connect` (incl. via `open`) records `AuditEvent.now(type: AuditEventType.connect, …host fields…, meta: {'source': source, 'via': 'cli-request'})` before calling `handlers.connect`.

- [ ] **Step 1: Write failing tests** (fake `CliHandlers` recording calls) — wrong token → `ok:false, code:4`, nothing called; trusted call ignores token; ambiguous label → `code:2` with 2 `candidates` summaries; unknown host → `code:2`; ad-hoc `user@h:22` via `connect` calls `connectAdHoc`; `open` with `yourssh://connect/web-1` calls `connect(source:'url')`; `open` rejects `yourssh://connect/..%2F..`, `yourssh://connect/`, `yourssh://exec/x`, `yourssh://connect/root@1.2.3.4` (no saved match) and `https://…` with `code:2` and no handler call; invalid JSON / 70 KiB line / unknown cmd → error response, and a following valid request still succeeds; `ls --tag prod` returns only tagged hosts and no secret keys; an audit row with `meta.source == 'cli'` is recorded for connect.
- [ ] **Step 2: Run** `cd app && flutter test test/services/cli/cli_server_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** `CliServer` and the abstract `CliHandlers`.
- [ ] **Step 4: Run** the test — Expected: PASS.
- [ ] **Step 5: Commit** `feat(cli): request handling, URL validation and auditing in CliServer`

### Task 4: Unix-socket listener with peer-uid check (macOS, Linux)

**Files:**
- Create: `app/lib/services/cli/cli_listener.dart` (interface), `app/lib/services/cli/cli_listener_unix.dart`, `app/lib/services/cli/peer_cred.dart`
- Test: `app/test/services/cli/cli_listener_unix_test.dart`, `app/test/services/cli/peer_cred_test.dart`

**Interfaces:**
- Consumes: Task 1 `CliEndpoint`, `writeToken`; Task 3 `CliServer.handleLine`.
- Produces:
  - `abstract class CliListener { Future<void> start(); Future<void> stop(); }` and `CliListener createCliListener(CliEndpoint ep, CliServer server)` (picks Unix or Windows).
  - `int? peerUidFromCred(Uint8List raw, String os)` — Linux `SO_PEERCRED` (`struct ucred {int pid; uint uid; uint gid}` → uid at offset 4), macOS `LOCAL_PEERCRED` (`struct xucred {u_int cr_version; uid_t cr_uid; …}` → uid at offset 4, require `cr_version == 0`); `int currentUid()` via FFI `getuid` from libc.
  - Listener behavior: create run dir 0700; if `cli.sock` exists and a connect attempt is refused → delete it, else (a live instance answers) throw `CliEndpointInUse`; bind `InternetAddress(path, type: unix)`, chmod socket 0600; per connection read one line (≤ 64 KiB, 5 s read timeout), reject peers whose uid ≠ `currentUid()` by closing without a response, write `handleLine` result, close; `stop()` closes and unlinks the socket.

- [ ] **Step 1: Write failing tests** — `peer_cred_test`: crafted byte buffers for linux/macos return the uid; wrong `cr_version` → null; short buffer → null. `cli_listener_unix_test` (skip on Windows): start in a temp run dir → a client `Socket.connect` + `version` request gets `{"app":…}`; socket file mode is `0600`, run dir `0700`; a stale socket file left from a dead listener is replaced on start; starting a second listener on the same endpoint while the first is live throws `CliEndpointInUse`; a client sending 70 KiB gets the connection closed and the listener still answers the next request; `stop()` removes the socket file.
- [ ] **Step 2: Run** `cd app && flutter test test/services/cli/` — Expected: FAIL.
- [ ] **Step 3: Implement** (`Socket.getRawOption(RawSocketOption(level, option, Uint8List(n)))`: Linux level `SOL_SOCKET`=1, `SO_PEERCRED`=17, 12 bytes; macOS level `SOL_LOCAL`=0, `LOCAL_PEERCRED`=0x001, 76 bytes).
- [ ] **Step 4: Run** the tests — Expected: PASS on macOS; CI runs them on Linux.
- [ ] **Step 5: Commit** `feat(cli): unix-socket listener with peer uid check`

### Task 5: Windows named-pipe listener

**Files:**
- Create: `app/lib/services/cli/cli_listener_windows.dart`
- Modify: `app/pubspec.yaml` (add `win32` if not already present)
- Test: `app/test/services/cli/cli_listener_windows_test.dart` (runs only on Windows; skipped elsewhere)

**Interfaces:**
- Consumes: Task 1 endpoint (`\\.\pipe\yourssh-cli-<SID>`), Task 3 `CliServer`.
- Produces: `class WindowsPipeCliListener implements CliListener` — `CreateNamedPipeW` with `PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE`, `PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS`, a `SECURITY_ATTRIBUTES` whose DACL grants `GENERIC_READ|GENERIC_WRITE` to the current user SID only; blocking accept/read/write run in a dedicated isolate that hands each line to the main isolate and writes back the response. `FILE_FLAG_FIRST_PIPE_INSTANCE` failure → `CliEndpointInUse`. Also `String currentUserSid()`.

- [ ] **Step 1: Write the failing Windows-only test** — start → a client opening the pipe with `CreateFileW` and sending `version` gets a response; a second listener throws `CliEndpointInUse`.
- [ ] **Step 2–4:** implement, then verify on the Windows CI runner by adding the test to a Windows job in `pr-test.yml` (`flutter test test/services/cli/cli_listener_windows_test.dart`) — Expected: PASS there.
- [ ] **Step 5: Commit** `feat(cli): named-pipe listener for Windows`

### Task 6: App wiring and single-instance forwarding

**Files:**
- Create: `app/lib/services/cli/app_cli_handlers.dart`, `app/lib/services/cli/single_instance.dart`
- Modify: `app/lib/main.dart:114-143` (desktop branch only), `app/lib/providers/session_provider.dart:179` (`connectAny` gains `String auditSource = 'app'`, threaded to where the connect audit row is written)
- Test: `app/test/services/cli/app_cli_handlers_test.dart`, `app/test/services/cli/single_instance_test.dart`

**Interfaces:**
- Consumes: Tasks 1–5; `SessionProvider.connectAny(Host, {String? initialCommand})`, `HostProvider.hosts`, `windowManager.show()/focus()`.
- Produces:
  - `class AppCliHandlers implements CliHandlers` (takes `SessionProvider`, `HostProvider`, a `Future<void> Function() focus`, the app version).
  - `Future<bool> forwardToRunningInstance(List<String> args, CliEndpoint ep)` — maps argv to a request (`yourssh://…` → `open`; no args → `version` used as a ping that also focuses), returns true when a live instance answered (caller then `exit(0)`).
  - In `main()` (desktop): before `runApp`, `if (await forwardToRunningInstance(args, ep)) exit(0);` after the first frame: `writeToken`, `createCliListener(ep, CliServer(...)).start()`; on `CliEndpointInUse` (lost a start race) forward and exit; record the app executable path in `<runDir>/app.path` for the CLI launcher; stop the listener on window close.

- [ ] **Step 1: Write failing tests** — `AppCliHandlers.connect` calls `connectAny(host, auditSource: 'cli')` then `focus`; `forwardToRunningInstance` against a test listener returns true and the server sees `open` with the URL; with no listener returns false within 1 s; two concurrent `forwardToRunningInstance` + listener starts end with one listener and one forwarded request.
- [ ] **Step 2: Run** `cd app && flutter test test/services/cli/` — Expected: FAIL.
- [ ] **Step 3: Implement** and wire `main.dart`.
- [ ] **Step 4: Run** the full suite `cd app && flutter test` — Expected: all pass.
- [ ] **Step 5: Commit** `feat(cli): start the CLI endpoint in the app and forward second launches`

### Task 7: `yourssh://` registration and delivery

**Files:**
- Modify: `app/macos/Runner/Info.plist` (`CFBundleURLTypes` → scheme `yourssh`), `app/macos/Runner/MainFlutterWindow.swift` (register `NSAppleEventManager` `kInternetEventClass/kAEGetURL` handler in `awakeFromNib`, forward the URL string over a `yourssh/url` `FlutterMethodChannel`; queue URLs received before Dart listens)
- Modify: `app/lib/main.dart` (listen on `yourssh/url`, call `CliServer.handleLine(trusted: true, source: 'url')` with an `open` request)
- Modify: `.github/workflows/release.yml` (Linux `.desktop`: `Exec=… %u`, `MimeType=x-scheme-handler/yourssh;`; Windows Inno Setup `[Registry]` entries under `HKCU\Software\Classes\yourssh` with `URL Protocol` and `shell\open\command` → `"{app}\yourssh.exe" "%1"` — find where the `.iss`/desktop file is generated)
- Test: `app/test/services/cli/url_channel_test.dart`

**Interfaces:**
- Consumes: Task 3 `open` handling, Task 6 forwarding (Windows/Linux deliver the URL as argv to a new process, which forwards it).
- Produces: method channel `yourssh/url`, method `open`, argument `String url`.

- [ ] **Step 1: Write failing test** — a mocked `yourssh/url` call with `yourssh://connect/web-1` reaches `CliServer` as a trusted `open` and connects; `yourssh://exec/x` does not.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the Dart listener, the Swift handler and the packaging entries.
- [ ] **Step 4: Run** the test; then manually on macOS: build, `open "yourssh://connect/<label>"` → tab opens. Linux/Windows registration verified in the release dry-run.
- [ ] **Step 5: Commit** `feat(cli): yourssh:// URL scheme on macOS, Windows and Linux`

### Task 8: The `yourssh` executable

**Files:**
- Create: `packages/yourssh_cli/bin/yourssh.dart`, `packages/yourssh_cli/lib/client.dart`, `packages/yourssh_cli/lib/output.dart`
- Test: `packages/yourssh_cli/test/client_test.dart`, `packages/yourssh_cli/test/output_test.dart`

**Interfaces:**
- Consumes: Task 1 protocol/endpoint.
- Produces:
  - `Future<int> runCli(List<String> argv, {required CliTransport transport, required AppLauncher launcher, required IOSink out, required IOSink err, required bool isTty, required Map<String,String> env})` — returns the exit code.
  - `abstract class CliTransport { Future<String> roundTrip(CliEndpoint ep, String requestLine); }` (Unix socket / named pipe implementations; throws `CliUnreachable` on refused/missing endpoint).
  - `abstract class AppLauncher { Future<void> launch(CliEndpoint ep); }` — macOS `open -b com.thangnm.yourssh`, others exec the path in `<runDir>/app.path`.
  - Commands: `connect <host>`, `ls [--json] [--tag T] [--filter Q]`, `version`, `open <url>`, `help`. `ls` prints a table `LABEL  USER@HOST:PORT  PROTOCOL  TAGS` (no color when `!isTty` or `NO_COLOR` is set) or the raw `hosts` array with `--json`.

- [ ] **Step 1: Write failing tests** (fake transport/launcher) — `connect web` sends `{"cmd":"connect","args":{"host":"web"}}` with the token from the token file and exits 0; ambiguous response → prints candidates to stderr, exit 2; unreachable → launcher called once, retried until a fake endpoint appears, exit 0; never appears within 15 s (use an injected clock) → exit 3 with "YourSSH is not running"; `ls --json` prints valid JSON identical to the result; `ls` table has no ANSI codes when `isTty` is false or `NO_COLOR=1`; unknown command → usage, exit 2; `version` prints CLI and app versions; protocol mismatch response → exit 3 with "update YourSSH".
- [ ] **Step 2: Run** `cd packages/yourssh_cli && dart test` — Expected: FAIL.
- [ ] **Step 3: Implement** `bin/yourssh.dart` (thin `main` → `runCli` with real transport/launcher), `client.dart`, `output.dart`.
- [ ] **Step 4: Run** `dart test`; then end-to-end on macOS: run the app (`flutter run -d macos`), `dart run packages/yourssh_cli/bin/yourssh.dart ls` lists hosts, `… connect <label>` opens a tab — Expected: both work.
- [ ] **Step 5: Commit** `feat(cli): yourssh executable with connect, ls, version and open`

### Task 9: Docs

**Files:**
- Modify: `CLAUDE.md` (new "CLI" section: package, endpoint, protocol, security model, URL scheme), `README.md` (usage examples), `CHANGELOG.md` (`[Unreleased]` → Added)

- [ ] **Step 1:** Write the sections from the final code (no aspirational content: packaging/install button are phase 2).
- [ ] **Step 2: Commit** `docs: describe the yourssh CLI and URL scheme`
