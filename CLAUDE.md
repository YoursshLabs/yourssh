# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Run (macOS / Windows / Linux)
cd app && flutter run -d macos
cd app && flutter run -d windows
cd app && flutter run -d linux

# Build
cd app && flutter build macos
cd app && flutter build windows
cd app && flutter build linux

# Lint / analyze
cd app && flutter analyze

# Tests
cd app && flutter test
cd app && flutter test test/services/sync_service_test.dart   # single test file
cd app && flutter test --name "pattern"                       # filter by test name
```

## Native RDP library

```bash
# Build + copy the Rust dylib/so/dll into packages/yourssh_rdp/assets/native/
bash packages/yourssh_rdp/build.sh   # macOS / Linux
pwsh packages/yourssh_rdp/build.ps1  # Windows

# Rust unit tests (no Flutter required)
cargo test --manifest-path packages/yourssh_rdp/rust/Cargo.toml

# Dart package tests (requires the dylib built above)
cd packages/yourssh_rdp && flutter test

# Regenerate the RDP feature screenshots in <repo>/screenshots/ — drives the
# real app against a local xrdp container; needs no macOS screen-recording
# permission (frames captured from the Flutter render tree). Prereqs in the
# test file header.
cd app && flutter test integration_test/rdp_screenshots_test.dart -d macos
```

## Architecture

The active codebase is `app/` — a Flutter app targeting macOS, Windows, and Linux. The in-app RDP client is implemented as the `packages/yourssh_rdp` Rust crate bridged via `flutter_rust_bridge` v2; the old `core/` Swift-bridge Rust library has been removed.

**Monorepo layout:**
- `app/` — the Flutter app
- `packages/yourssh_rdp` — **Rust RDP client** (IronRDP 0.15, flutter_rust_bridge v2); exposes `RdpClient` + `RdpConfig`, a `StreamSink<RdpEvent>` event bus, and `rdp_lib_version()`; `RdpClient.ensureInitialized()` lazily loads the native library + inits the FRB runtime on first RDP connect (no init in main.dart); `RdpConfig.expectedFingerprint` carries the pinned cert fingerprint — the Rust engine verifies it post-TLS / **pre-CredSSP** and aborts with `RdpEvent.certMismatch` before any credentials are sent (TLS itself uses no cert verification — the pin is the only server check); `RdpEvent.connected` carries the **server-negotiated** desktop size (may differ from the request); dirty rects are inclusive-rectangle corrected (+1) and clamped before extraction; the run loop peeks every X224 frame for an MCS Disconnect Provider Ultimatum (server-side session end: remote sign-out / session takeover / admin disconnect) and turns it into a graceful `RdpEvent.disconnected` — ironrdp-session 0.9's x224 processor would otherwise surface it as a raw decode error; build scripts produce `libyourssh_rdp.dylib` / `.so` / `.dll` which the Dart `NativeLoader` resolves at runtime from the app bundle (release) or `assets/native/` (dev); the built libraries are **not tracked in git** (`assets/native/` is gitignored — run `build.sh`/`build.ps1` once after clone; CI builds them fresh)
- `packages/dartssh2` — **local fork** of dartssh2; overrides the pub.dev version via `dependency_overrides` in `app/pubspec.yaml`; adds `signAsync()` for agent-backed auth and SSH agent forwarding (sends `auth-agent-req@openssh.com` on shell channels only — never exec; accepts server-opened `auth-agent@openssh.com` channels via `SSHClient.agentHandler`; a refused request is non-fatal and surfaces as `SSHSession.agentForwardingRefused`); implements strict KEX (`kex-strict-c/s-v00@openssh.com`, CVE-2023-48795 "Terrapin" mitigation: sequence numbers reset after every NEWKEYS, non-KEX messages during the initial key exchange terminate the connection, KEXINIT must be the first packet); adds `OpenSSHEd25519KeyPair.generate()` and a passphrase-encrypting `toPem({passphrase})` (bcrypt-pbkdf + aes256-ctr; null passphrase output unchanged, interop-verified against real `ssh-keygen -y`)
- `packages/flutter_pty` — **local fork** of flutter_pty 0.4.2 (also via `dependency_overrides`); patches `src/flutter_pty_win.c` so the Windows command line doesn't duplicate `argv[0]` (upstream issue #19 — broke keyboard input in the local PowerShell terminal)
- `packages/xterm` — **local fork** of xterm 4.0.0 (also via `dependency_overrides`); patches: (1) `lib/src/ui/custom_text_edit.dart` passes `viewId: View.maybeOf(context)?.viewId` to `TextInputConfiguration` (upstream issue #207 — newer Flutter engines on Windows reject a text-input client without a viewId, so printable keys never reached any `TerminalView` while Enter/Tab/paste still worked); (2) copy/paste reachability (issue #43) — `shortcut/shortcuts.dart` adds Ctrl+C → `TerminalCopyAndClearIntent` and Ctrl+Shift+V paste alias on Windows/Linux, `shortcut/actions.dart` adds `_CopySelectionAndClearAction` (enabled only with an active selection; copies then clears it so the next Ctrl+C reaches the shell as SIGINT — without a selection `ShortcutManager` ignores the key and it falls through as ^C), `ui/gesture/gesture_handler.dart` un-aliases tertiary taps from the secondary-tap callbacks (middle clicks also reported to mouse-mode apps as `TerminalMouseButton.middle`, not right), and `terminal_view.dart` pastes the clipboard on middle-click unless `readOnly`
- `packages/yourssh_plugin_api` — abstract plugin interface (`YourSSHPlugin`, `YourSSHPluginContext`)
- `packages/yourssh_devops` — DevOps plugin (containers (Docker/K8s), network tools, Cloudflare tunnel, mail catcher, MCP server, S3 browser)
- `packages/yourssh_web_tools` — Web Tools plugin (in-app browser over port-forwarded HTTP)
- `packages/yourssh_snippets` — Snippets plugin
- `packages/yourssh_script_engine` — JS plugin runtime (QuickJS FFI, HookBus, bridges, PluginLoader, PermissionGuard)

**Data flow:**

```
Flutter UI (widgets/screens)
  └── Providers (ChangeNotifier, via provider package)
        └── SshService / StorageService
              └── dartssh2 (SSH, SFTP, port forwarding) [local fork]
              └── flutter_secure_storage (Keychain / Credential Manager)
              └── shared_preferences (host list, app settings)
```

**Providers** (`app/lib/providers/`):
- `HostProvider` — CRUD for saved SSH hosts; fires `onMutation` callback to trigger sync push; `onHostDeleted(hostId)` fires before removal so dependents tear down (wired to `PortForwardService.stopForHost`)
- `SessionProvider` — manages the unified `AppSession` tab list (SSH sessions, local PTY shells, **and RDP tabs**; `sessions` / `sshSessions` / `activeSshSession` accessors); wires key lookup, auto-reconnect, tmux, and host-key verification via callbacks set in `main.dart`; `onSessionDropped(AppSession, reason)` fires when a session drops without a pending auto-reconnect (not on user-initiated close; RDP drops covered via `_watchRdpStatus`, which also writes RDP connect/disconnect audit rows with `source: rdp`) — wired to the notification center; `connectRdp` lazily inits the Rust bridge (`RdpClient.ensureInitialized`, failure = error tab), passes the pinned fingerprint via `rdpPinLookup` for the pre-auth Rust-side check, and routes pin mismatches through `rdpCertMismatchHandler` (accept → auto-reconnect); closing the last RDP tab of a host calls `_ssh.disconnect(hostId)` so a tunneled session's bastion client is released; tab metadata (rename/color/pin) persists for SSH **and** RDP via the shared `_persistTabMetadata`/`_applyTabMetadata`; `handleAgentForwardingEvent` tracks per-session `AgentForwardingState` (ready/active/fallback/refused) shown as a key icon on `SessionTab`; server refusal also lands in the notification bell; local shells go through the injected `LocalShellService` (`newLocalSession` / `restartLocalSession`; the `localShell` setter wires the service's PTY-exit notifications into the provider's notify)
- `KeyProvider` — SSH key entries (path + optional passphrase + optional linked certificate path)
- `PortForwardProvider` — local/remote/dynamic `PortForward` tunnel configs (persistent rules; `add`/`update`/`delete` persist, `setStatus`/`setConnections` are transient runtime state pushed by `PortForwardService`); `ready` future completes when persisted rules are loaded (auto-start waits on it)
- `TunnelProvider` — active `TunnelConfig` sessions (runtime state, separate from PortForwardProvider)
- `SnippetProvider` — reusable command snippets (managed by `yourssh_snippets` plugin)
- `SyncProvider` — holds Supabase sync config (URL/key, optional passphrase, status); `enabled` is derived from `isSupabaseConfigured` — no separate stored flag; passphrase stored in secure storage via `StorageService`
- `KnownHostsProvider` — persists known host fingerprints; exposes `pendingChallenge` for TOFU dialog
- `SettingsProvider` — app-wide prefs (auto-reconnect, tmux, hotkeys, feature flags for DevOps/WebTools/Snippets)
- `TerminalLayoutProvider` — split layout (none/horizontal/vertical), input bar visibility, and the right-side workspace panel via the `SidePanel` enum (`none`/`snippets`/`terminalConfig`; `toggleSidePanel()` opens one panel at a time — opening one closes the other; `toggleSnippetsPanel()` kept as alias). The snippets panel and the terminal-appearance config panel (`TerminalConfigPanel`, toggled by the tune icon; hosts `TerminalAppearanceControls`, the theme/font-size/font controls shared with Settings → Terminal) both render inside the shared `WorkspaceSidePanel` frame (340px, header + close)
- `LocalFilePanelProvider` — local filesystem state for the dual-panel SFTP view
- `SftpPanelProvider` — remote SFTP panel state (current path, directory listing)
- `SftpTransferProvider` — in-progress upload/download transfer queue and status
- `CommandHistoryProvider` — per-host command history for terminal autocomplete
- `AiChatProvider` — AI chat sidebar; supports multiple providers (`AiProvider` enum: `anthropic`, `openai`, `gemini`); API keys and model selection stored per-provider in `SharedPreferences`
- `PluginProvider` — activates/deactivates registered plugins; wraps `PluginContextImpl` for each
- `PluginEngineProvider` — wires `ScriptEngineService` into the Flutter state tree; surfaces loaded JS plugins, enabled state, and per-plugin console logs to the UI
- `RecordingProvider` — recording library state; `startRecording(session)` / `stopRecording(sessionId)`; `refreshLibrary()` scans disk for `.cast` files; `isRecording(sessionId)` for UI indicators; wired to `SessionProvider` via `recordingStart` callback in `main.dart`
- `ShellIntegrationProvider` — per-session shell-integration state (cwd + command list) keyed by `sessionId`; `handleOsc(sessionId, code, args, absoluteCursorY)` routes xterm `onPrivateOSC` events through `ShellIntegrationService` into `ShellSessionState`; exposes `cwdFor`/`maybeStateFor` and a per-session `revisionFor` so consumers `context.select` to their own session; `clear(sessionId)` on shell close / disconnect
- `UpdateProvider` — in-app update flow: launch check + periodic re-check (`startPeriodicChecks()`, `Timer.periodic` every `checkInterval`, default 6h) + window-focus re-check (wired in `main.dart.onWindowFocus`) + manual check — auto checks all debounced 24h via `last_update_check` in `SharedPreferences`; semver compare, download progress, and install hand-off; `showBanner` derived from `status == available && version != dismissedVersion`; `dismiss()` persists per-version; surfaces state to `UpdateBanner` and the Settings Updates section
- `AuditProvider` — filter state (host/type/time-range/search) + lazy paging (200/page) over `AuditService` for the Audit Log screen; `exportCsv`/`exportJson` of the active filter
- `NotificationCenterProvider` — in-memory store behind the notification bell in the top tab bar (`NotificationBell` widget); `add()` dedupes via `AppNotification.dedupeKey` (`update:<version>`, `disconnect:<sessionId>`) and caps at 50 items; `markAllRead()` on panel open, `clearAll()` / `remove(id)`; fed in `main.dart` by an `UpdateProvider` listener (one update notification per version) and `SessionProvider.onSessionDropped`

**Services** (`app/lib/services/`):
- `SshService` — owns `SSHClient` and `SSHSession` maps keyed by host ID; handles connect, shell, exec, sftp, `testConnection` (TCP+auth without opening a shell), disconnect; `ensureClient(host)` returns the open client or auto-connects with stored credentials (evicts dead cached clients; resolves `Host.keyId` via the `defaultKeyLookup` callback, host keys via `defaultHostKeyVerifier`, and `Host.jumpHostIds` via `defaultJumpHostLookup` so SFTP/exec/port-forward auto-connects tunnel through the bastion chain like sessions do). **Multi-hop jump chains:** `connect(jumpChain:)` (`JumpHop = (host, keyEntry)`) dials each hop over the previous hop's `forwardLocal`, authenticating + host-key-verifying every hop; clients are cached by chain-prefix key (`a`, `a>b` — `B through A` ≠ direct `B`) and torn down deepest-first by refcount (`_teardownJumpChain`); cycle-guarded (duplicate hop or target-in-chain throws). `testConnection` dials the chain with per-hop temp clients closed in `finally`. An unresolved hop fails the connect (no silent skip)
- `PortForwardService` — runtime engine for port-forward rules: starts/stops local (`ServerSocket` → `forwardLocal` pipe), remote (`forwardRemote` → local socket pipe), and dynamic SOCKS5 (`forwardDynamic`) tunnels over a `TunnelTransport` abstraction (`SshTunnelTransport` wraps `SSHClient`; fakes in tests); watches `client.done` per host and auto-reconnects with exponential backoff (2 s doubling, 30 s cap; local listeners stay bound across drops); in-flight dials deduped per host; pushes state via `onStatus`/`onConnections` callbacks into `PortForwardProvider`; `autoStartAll` runs after the provider's `ready` future; `stopForHost` wired to host deletion. Design: `docs/superpowers/specs/2026-06-05-port-forwarding-runtime-design.md`
- `StorageService` — host list as JSON in `SharedPreferences`; all secrets via `_saveSecret/_loadSecret/_deleteSecret` helpers (secure-first: write to `FlutterSecureStorage`, purge stale prefs copy on success, fall back to prefs on error); exposes `saveGenericSecret` / `loadGenericSecret` / `deleteGenericSecret` for app-scoped secrets (e.g., `sync_passphrase`)
- `CertificateKeyPair` — implements `SSHKeyPair`; wraps a PEM private key with a separate OpenSSH certificate file (base64 blob); used by `SshService` when `AuthType.certificate`
- `SyncService` — push/pull host data encrypted via `SyncEncryption` to a Supabase table; retries failed pushes every 30 s via timer; concurrent push while one is in-flight sets `sync_pending_push` instead of silently dropping the mutation; `disableAndDelete()` returns `String?` (remote delete error, or null on success) and calls `clearSupabaseConfig()` on the provider; `buildPayload` strips `detectedOs` from host JSON before upload
- `SupabaseService` — thin HTTP wrapper around Supabase REST API (upsert/fetch/delete a single row in `sync_data` table); raw `http` calls, no `supabase_flutter` SDK
- `P2PSyncService` — LAN sync via a one-shot HTTP server; `getLocalInterfaces()` enumerates non-loopback IPv4 interfaces with friendly `displayName` (Wi-Fi / Ethernet / VPN); `startServer(encryptedPayload, hostAddress)` binds on a random port and returns the full URL; server closes after the first successful `GET /sync` response; `onServerError` callback for mid-transfer errors; `fetchPayload(url)` HTTP GET with 5 s connect + 10 s body timeout
- `P2PSyncEncryption` — AES-256-GCM for LAN sync; `generateKey()` returns a random 32-byte key embedded in the QR URL (no PBKDF2 — key exchanged out-of-band via QR scan)
- `LocalShellService` / `PtyRunner` — local terminal via `flutter_pty`
- `HotkeyService` — app hotkey registration via `hotkey_manager` with `HotKeyScope.inapp` (system scope used keybinder/XGrabKey on Linux — dead on Wayland, stole combos system-wide elsewhere; issue #46); hotkey names (`new_session`, `close_session`, `next_session`, `prev_session`, `toggle_input_bar`, `split_horizontal`, `split_vertical`, `command_palette`) configured in `SettingsProvider`; `shouldSwallowKeyEvent` lets terminal views drop a combo that already fired as a hotkey so it never reaches the shell
- `SftpFileOpsService` — SFTP file operations: rename, delete, mkdir, createFile, `statMode` (stat fallback when listings omit permissions), and `chmod` with a hardened recursive walk (`chmodWalk`, callback-injected for tests) — `listWalkChildren` is the single classification policy shared with recursive delete (entries whose listing omits the mode are classified via lstat; symlinks are reported as symlinks and never followed — SETSTAT would chmod the link target), directory modes are applied post-order so a restrictive mode can't strip the walk's own r/x mid-descent, file chmods run in batches of 8
- `os_detection.dart` — pure (no Flutter/IO): `parseOsReleaseId` / `normalizeDistroId` map `/etc/os-release` IDs to icon keys (`kOsIconKeys`, aliases like `amzn`→`amazon`, unknown→`linux`); `osIconAsset` resolves `assets/os/<key>.svg` for the hosts dashboard and `SessionTab`; `SshService.detectOs` runs the distro probe when `uname` says Linux, and `SessionProvider` re-detects when `detectedOs` is null **or** generic `'linux'`
- `SftpTransferService` — chunked upload/download with progress callbacks
- `ExternalEditService` — "open with external app" for SFTP files: downloads to a per-session temp dir, launches the OS default app (`url_launcher`) or a specific app (`openExternalWith`), polls mtime every 2 s and auto-uploads changes back to the server; `sftp_file_inspector.dart` (pure) decides which files the in-app editor refuses (binary extension, > 5 MB, null byte in first 8 KB)
- `AppDiscoveryService` — discovers installed applications for a given file path, filtered by MIME type; per-extension cache; macOS uses `LSCopyApplicationURLsForURL` via a `yourssh/app_discovery` Flutter method channel registered in `MainFlutterWindow.awakeFromNib` (NOT AppDelegate — its lifecycle overrides never fire in this app), Linux parses XDG `.desktop` files in Dart, Windows uses PowerShell registry queries
- `McpGatewayService` — starts a remote MCP server over SSH exec and forwards a local port to it
- `CloudflareTunnelService` — manages `cloudflared` tunnel process lifecycle
- `MailCatcherService` — connects to a remote MailCatcher SMTP instance via port forward
- `NetworkStatsService` — polls SSH exec to gather network interface stats for the overlay
- `NotificationService` — wraps `local_notifier` for desktop notifications
- `WebToolsService` — in-app HTTP requests through a port-forwarded connection
- `RdpTunnelProxy` — one-shot loopback TCP proxy for SSH-tunneled RDP connections; `start(opener)` binds a random loopback port, calls `opener()` to get the SSH-forwarded `TunnelEnd` (`stream`/`sink`/`close`), and pipes traffic; teardown is symmetric — either side ending destroys both sockets and fires `onClosed` exactly once (suppressed on explicit `stop()`), letting `RdpSession.markTunnelClosed()` set the correct error message; both sockets' `done` futures are pre-guarded so a peer RST can't raise an unhandled zone error
- `SystemAgentProxy` — proxies SSH agent socket for `AuthType.agent`; `roundtrip(bytes)` raw passthrough (frame/unframe only, payload never parsed) used by agent forwarding
- `AgentForwardingHandler` — serves forwarded `auth-agent@openssh.com` channels when `Host.agentForwarding` is on: relays each request verbatim over a fresh `SystemAgentProxy` connection (connection-per-request — agent protocol is serial per connection), falling back to a memoized `SSHKeyPairAgent` built from app-Keychain keys (`loadKeychainKeyPairs`; loader wired from `KeyProvider` + stored passphrases in `main.dart` via `SshService.keychainIdentitiesLoader`) only when the agent connect fails; fires `onRequestServed(usedFallback)` after each served request (feeds the per-session forwarding state); attached to the destination client only in `SshService.connect` (never jump clients or `testConnection` — ProxyJump semantics); a server refusal prints a yellow warning in the terminal and the session continues. `loadKeyPairsFromFile` is the shared PEM+passphrase loader also used by `_resolveIdentities`
- `agent_probe.dart` — pure pre-connect probe (`probeAgentStatus`) behind the host panel's `AgentStatusLine` — reports system-agent identity count, Keychain-fallback key count, or nothing-to-serve; never throws (every failure maps to a displayable result)
- `KeyGenService` — SSH key generation: Ed25519 pure-Dart (the fork's `OpenSSHEd25519KeyPair.generate()` + `toPem(passphrase:)`), RSA-4096/ECDSA-P256 via `ssh-keygen` (`probeSshKeygen` gates the panel options when the binary is missing); `buildDeployCommand` (ssh-copy-id-style, `grep -qxF` idempotent, `EXISTS`/`ADDED` marker) used by `DeployKeyDialog` over `SshService.exec`; generated keys land in `Documents/YourSSH/keys` with mode 600 and the passphrase saved as `pp_<keyId>` via `KeyProvider.savePassphrase` (callback wired to `StorageService` in main.dart — `addKeyFromFile` returns the created entry)
- `RecordingService` — writes asciicast v2 (`.cast`) files; tracks active recordings keyed by `sessionId`; passive intercept pattern — `SshService` always calls `writeOutput()` / `onShellClosed()`, which no-op when not recording; when `redact:` is on (effective = `SettingsProvider.recordingRedactionEnabled` AND `Host.recordingRedaction`, both default true; sampled once at start via `RecordingProvider.redactionPolicy` wired in main.dart with a fresh `HostProvider` lookup — the session's Host snapshot goes stale after a panel edit), output is line-buffered (split at the last newline, start-once `flushDelay` timer, default 500 ms, stop flushes the tail) and passed through `AuditRedactor.redact()` before writing — coalesces events per line, which also strips keystroke timing; ANSI escapes inside a secret and a secret straddling a flushDelay boundary defeat the regexes (defense-in-depth, not a guarantee)
- `ShellIntegrationService` — pure (no Flutter/IO): `parseOsc(code, args)` maps xterm `onPrivateOSC` to a typed `ShellOscEvent` (OSC 7 cwd, OSC 133 A/D; C ignored); `buildInjectionScript()` is the guarded one-line bash/zsh prompt-hook installer (auto-on, opt-out via `Host.shellIntegration` + `SettingsProvider.shellIntegrationEnabled`), delivered **invisibly** via a two-phase handshake: `buildBootstrapLine()` (short line that disables tty echo and blocks in `read -rs`, printing `__YS_RDY__`/`__YS_DONE__` sentinels) + `buildPayloadLine({includeInstaller, workingDir, envVars})` (the installer plus the per-host session-template setup — `cd -- '<dir>'` + `export K='v'`, single-quote-escaped via `shQuote`, keys checked by `isValidEnvKey`; a failing cd prints a warning placed *after* the DONE sentinel so it survives the gate discard; consumed by `read` so never echoed). `SshService.openShell` wires `terminal.onPrivateOSC` and injects only when `injection_gate.dart`'s `InjectionReadiness` confirms the line editor is reading (bracketed-paste `ESC[?2004h` toggle + settle, bare-`\n` probe fallback for bash ≤ 5.0; skipped on alt-screen/user typing/never-confirmed) while `InjectionGate` withholds and discards the bootstrap echo; `path_completion.dart` (pure) plans cwd-aware path completion for the input bar over `SshService.listDirectory`. Design: `docs/superpowers/specs/2026-06-03-invisible-shell-integration-design.md`
- `AuditService` / `AuditRedactor` — local SQLite audit trail (`sqlite3` + `sqlite3_flutter_libs`, WAL, `<app-support>/audit.db`): `connect`/`disconnect`/`exec`/`input` events with denormalized host fields; commands pass `AuditRedactor` (pure regex masking: `key=value` secrets incl. prefixed `PGPASSWORD=`, Bearer tokens, `sshpass -p`, mysql/mariadb attached `-p`, URL userinfo — psql `-p` is the port, deliberately excluded) **before** insert; every write fail-soft (never breaks SSH ops); `SshService.exec` takes `auditSource` (`'app'` default; `'bulk'`/`'devops'`/`'plugin:<id>'`/`'plugin:js'` threaded by callers; `null` = skip — used by the network-stats poll so it can't flood the log); connect failures logged only when no retry is scheduled; retention pruned at startup (`auditRetentionDays`, default 90, 0 = forever); CSV/JSON export of the filtered view
- `UpdateService` — in-app update glue: `fetchLatestRelease()` (GitHub `releases/latest`, stable-only), pure `isNewerVersion` (semver, fail-closed on blank) and `assetForPlatform` (OS/arch → release asset; macOS arm64-only → null on Intel), `downloadAsset` (streamed to Downloads with progress, cleans up partial file), `launchInstaller` (macOS: strip `com.apple.quarantine` + `open` DMG; Windows: run installer `.exe`; Linux: `xdg-open`); throws typed `UpdateException`; takes an injectable `http.Client` for testing

**Utils** (`app/lib/util/`):
- `file_mode.dart` — POSIX mode helpers: `modeToOctal` / `parseOctal` (3–4 octal digits only — shorter is a partially-typed mode and never parses), the 9 `kMode*` permission-bit constants used by `PermissionsDialog`'s rwx grid, and `chmodLocal` (system `chmod`, macOS/Linux; callers hide the menu item on Windows)
- `app_launcher.dart` — `launchFileDefault` (OS default app via url_launcher), `launchFileWithApp` (macOS `open -a` / Windows `Process.run` / Linux direct exec), `pickApplication` (file_selector) — shared by `ExternalEditService` and the local file panel
- `terminal_appearance.dart` — `resolveTerminalAppearance` merges per-host theme/font/size overrides with the global Settings → Terminal values (unknown theme name → global, not catalog[0]); consumed by `terminal_view.dart` with a fresh-host lookup (HostProvider absent in tests → session snapshot)

**Key models** (`app/lib/models/`):
- `AppSession` — abstract base interface for all session types; provides `id`, `tabLabel`, `customLabel`, `colorTag`, `isPinned`; implemented by `TerminalSession` (SSH + local shells) and `RdpSession`
- `Host` — connection profile (host, port, username, `AuthType`: `password` / `privateKey` / `certificate` / `agent`; `agentForwarding` opt-in per host, default off; `recordingRedaction` opt-out for secret masking in recordings (default on, AND-ed with the global setting); `jumpHostIds` ordered jump chain (bastion → … → target — legacy scalar `jumpHostId` migrates on load and is dual-written to JSON for cross-version sync; `jumpHostId` getter returns the first hop); `protocol` (`HostProtocol.ssh` / `rdp`), `domain`, `rdpSecurity` (`RdpSecurityMode`: `auto`/`nla`/`tls`) for RDP hosts; session template fields — `workingDir` + `envVars` delivered invisibly via the shell-integration handshake, `startupSnippet` typed visibly after DONE (skipped under tmux and on handshake abort), `terminalThemeId`/`fontFamily`/`fontSize`/`termType`/`tmuxOverride` nullable per-host overrides falling back to globals; `hasTemplateSetup` drives the handshake when shell integration is off)
- `SshSession` — wraps an xterm `Terminal`; bridges `dartssh2` shell I/O to the widget; has `SessionStatus` (connecting/connected/disconnected/error) and reconnect attempt counter
- `RdpSession` — one RDP tab (`extends ChangeNotifier implements AppSession`); holds `RdpClient`, `Uint8List framebuffer`, `ui.Image? image` (latest decoded frame), `RdpSessionStatus`, `certFingerprint`, `certCheckCallback` for TOFU gating (result ignored if a Disconnected/Error landed during the dialog — never flips a terminal status back to connected), `onCertMismatch` (pre-auth pin mismatch → re-trust + auto-reconnect flow); framebuffer is **reallocated to the server-negotiated size** from the Connected event (frame coordinates arrive in that space; out-of-bounds patches are dropped, not crashed); decode is one-at-a-time latest-wins (no per-patch full decode pileup), old `ui.Image`s disposed on replace and on close; `close()` bounds `client.disconnect()` with a 5 s timeout so `tunnelProxy.stop()` always runs; `markTunnelClosed()` called by the proxy when either pipe side collapses
- `SshKeyEntry` — key file path, optional passphrase, optional `certificatePath` for cert auth
- `AgentForwardingState` — enum (`off`, `ready`, `active`, `fallback`, `refused`); mutable on `SshSession`; drives the key icon on `SessionTab` and the notification bell entry
- `PortForward`, `TunnelConfig`, `Snippet`, `KnownHost`, `NetworkStats`, `LocalEntry`, `SftpEntry`, `SftpTransferItem` — `SftpEntry.mode` / `LocalEntry.mode` carry the raw st_mode from listing/scan time (null when the server/stat omits it) so the permissions dialog never re-stats at open; a null mode makes the dialog warn and gate Apply instead of defaulting to 000
- `ChatMessage`, `AiProviderConfig` — AI chat models
- `ToolResult` — structured result from AI tool calls
- `RecordingEntry` — immutable metadata for one `.cast` file; `hostTitle` and `recordedAt` parsed from path (`{basePath}/{user}@{host}/session_YYYY-MM-DD_HH-mm-ss.cast`)
- `AuditEvent` — one immutable audit row (`AuditEventType`: connect/disconnect/exec/input; denormalized host fields, redacted command, exit code, JSON `meta` with `source`/`error`)

**UI entry point:** `app/lib/main.dart` — instantiates services and long-lived providers, wires callbacks between them (key lookup, host-key verifier, sync-on-mutation), then mounts `MainScreen` under `MultiProvider`. The app is dark-only (`ThemeMode.dark`); theme constants live in `app/lib/theme/app_theme.dart` (`AppColors`).

**Navigation:** `MainScreen` (`app/lib/screens/main_screen.dart`) renders a top tab bar (pinned Home/SFTP + scrollable SSH session tabs) and a left sidebar. The session tab itself is `SessionTab` (`app/lib/widgets/session_tab.dart`, extracted for testability): health dot, distro/OS glyph (fresh `detectedOs` looked up from `HostProvider` — the session's `Host` snapshot goes stale after `copyWith`), recording/color dots, rename, context menu, middle-click close (pinned tabs protected). `NavSection` enum: `hosts`, `keychain`, `portForwarding`, `sftp`, `knownHosts`, `recordings`, `audit`, `settings`, `plugins`. Each maps to a top-level screen widget under `app/lib/widgets/`. Both SFTP panels share `EntryContextMenu` (`app/lib/widgets/entry_context_menu.dart`) — Open / Open with / View / Edit / Copy to target (with up-front disabled reasons from `_copyBlockReason`, incl. the same-folder block) / Refresh / New folder / Permissions (`PermissionsDialog`) / Rename / Delete. The host panel's CONNECTION CHAIN section is `HostChainEditor` (`app/lib/widgets/host_chain_editor.dart`) — pure-presentational Termius-style **multi-hop** chain (hop cards → arrows → destination card, persistent Add-a-Host picker that excludes hosts already in the chain, per-hop remove ×, key icon on the last hop when agent forwarding is on, Clear resets to direct); writes the full ordered id list back via `onChanged` to the panel's `_jumpHostIds`. `HostDetailPanel` is the **single host editor** (the old `AddHostDialog`/`HostListPanel` were dead code and removed): an SSH/RDP `SegmentedButton` at the top switches protocol (port auto-flips between `HostProtocol.defaultPort`s only when still on the other default); RDP mode shows domain / RDP-security / single-hop SSH-tunnel dropdown (stale tunnel ids render as "Direct connection", never a dropdown assert) and hides all SSH-only sections; `_save` preserves `protocol`/`domain`/`rdpSecurity`/`createdAt`. The shared `RdpBadge` widget (`app/lib/widgets/rdp_badge.dart`) marks RDP hosts on dashboard cards, list rows, and the panel header. `RdpWorkspace` supports **fullscreen** (`isFullscreen` + `onFullscreenChanged(bool)` — the widget reports intent, `MainScreen._setRdpFullscreen` owns `windowManager.setFullScreen` and collapses the app chrome to just the workspace): toolbar button enters (enabled only while connected), an auto-hiding hover pill at the top screen edge (mstsc-style; flashes 2.5 s on entry) exits, and the workspace auto-requests windowed mode when the session leaves `connected`; `MainScreen.build` also force-exits if the active tab stops being the RDP session (tab switch/close via hotkey), so the user can never be trapped chrome-less. Dashboard host actions are protocol-aware: SFTP/Test hidden for RDP, bulk Run/Push filter to SSH hosts (with a skipped-count snack), CONNECT ALL counts live RDP tabs, Duplicate keeps the RDP fields, Copy URL uses `rdp://` for RDP hosts.

**Bulk actions:** the hosts dashboard's SELECT mode drives `app/lib/widgets/bulk/` — `BulkActionBar` (SELECT ALL / CLEAR / CONNECT ALL / RUN COMMAND / PUSH FILES / DONE; action cluster right-anchored, scrolls when narrow), `BulkRunDialog` + `BulkRunController` (parallel exec with bounded concurrency, 30 s per-host timeout, per-host failure isolation), `BulkDiffView` (groups identical outputs against a promotable baseline, side-by-side compare), `BulkPushDialog` (multi-host upload via `SftpTransferService.uploadDirectory(overwrite: true)`), `BulkHostStatusList` (shared per-host status rows). Closing a dialog mid-run confirms, cancels queued hosts, and lets in-flight operations finish.

**Code editor:** `CodeEditorScreen` renders a Monaco editor via `webview_flutter` using the bundled `assets/monaco_editor.html`.

## Plugin system

Two plugin types coexist:

### Dart plugins (compile-time)

Compiled into the app. Registered in `app/lib/plugins/plugin_registry.dart` (`kRegisteredPlugins`). To add one:
1. Add the package to `app/pubspec.yaml` dependencies
2. Import and instantiate in `plugin_registry.dart`

Each implements `YourSSHPlugin` (from `yourssh_plugin_api`):
- `buildUI(context, pluginContext)` — plugin's widget
- `onActivate(ctx)` / `onDeactivate()` — lifecycle hooks
- `minApiVersion` — checked at runtime against `kApiVersion`

`YourSSHPluginContext` exposes: `activeSessions`, `activeSession`, `execCommand(sessionId, cmd)`, `sendInput(sessionId, text)` (types text into the session's terminal — used by Snippets to insert a snippet into the focused session), namespaced `savePreference` / `getPreference`.

### JS plugins (disk-based, runtime)

Loaded at runtime from a plugins directory via `packages/yourssh_script_engine`. No rebuild required.

**Key components:**
- `PluginManifest` — parses and validates `plugin.json` (name, version, permissions, hooks declared)
- `QuickJsRuntime` — Dart FFI bindings for the QuickJS C engine; evaluates JS, calls hooks, returns structured results
- `JsRuntimeRegistrar` — registers all Dart → JS bridge APIs into a `QuickJsRuntime`
- `HookBus` — typed event bus; supports `transform` (modify data), `intercept` (block), and `observe` (side-effect) hooks; wired into `SshService` for `terminal.output`, `terminal.input`, and session lifecycle events
- `PluginLoader` — scans a directory for `plugin.json` manifests, loads plugins, watches the filesystem for changes and hot-reloads modified plugins
- `PermissionGuard` — enforces manifest-declared permissions before dispatching bridge calls
- `PluginErrorTracker` — circuit breaker: counts consecutive errors per plugin; disables the plugin if it exceeds the threshold
- `PluginUiRegistry` — plugins can register Flutter widgets by calling the `ui.register(id, widgetSpec)` JS API; the app renders these in the plugin manager

**Bridges (Dart APIs exposed to JS):**
- `SshBridge` — `ssh.exec(sessionId, cmd)`, `ssh.write(sessionId, data)`
- `SftpBridge` — `sftp.list(sessionId, path)`, `sftp.readFile`, `sftp.writeFile`
- `StorageBridge` — `storage.get/set/delete(key)` (namespaced per plugin)
- `UiBridge` — `ui.showNotification(msg)`, `ui.register(id, spec)`

**UI screens:**
- `plugin_consent_dialog.dart` — shown on first load; user must accept declared permissions
- `plugin_manager_screen.dart` — lists installed JS plugins, enable/disable toggle, reload action
- `plugin_console_screen.dart` — per-plugin `console.log` output viewer

## Sync feature

**Supabase sync** (cloud): opt-in. Host data is AES-256-GCM encrypted before upload. The payload uses format `v1:` with a per-row random 16-byte salt and PBKDF2-HMAC-SHA256 (100k iterations) over `passphrase + " " + anonKey` (the optional user passphrase mixes into the KDF — without it, anyone holding the public anon key could decrypt). Legacy rows (no `v1:` prefix) still decrypt using the old fixed-salt + anon-key-only derivation, so existing data migrates on next write. `SyncService.push` fires from `HostProvider.onMutation` and retries every 30 s on failure (`sync_pending_push` flag). `SyncService.pull` runs on `WindowFocus` and only applies if `remote.updated_at > last_push_at`. `SyncProvider.enabled` is derived from `isSupabaseConfigured` — no separate flag.

**P2P sync** (LAN): `P2PSyncService` starts a one-shot HTTP server on a random port and encrypts the host list with a random 32-byte AES-256-GCM key (`P2PSyncEncryption.generateKey()`). Both the URL and the key are encoded in the QR code. The receiving device scans the QR code, fetches the payload via HTTP (5 s connect + 10 s body timeout), decrypts it, and imports the hosts. The server closes automatically after one successful transfer. `NetworkInterfaceInfo` discovers available LAN interfaces (Wi-Fi / Ethernet / VPN) so the sender can choose which IP to advertise.

## Credential storage

Passwords use a secure-first strategy: `StorageService` writes to `FlutterSecureStorage` (Keychain on macOS, Credential Manager on Windows) first, and on success purges any stale plaintext copy from `SharedPreferences` (left over from prior fallbacks). Only if secure storage throws does it fall back to writing plaintext to `SharedPreferences`. Reads prefer secure storage, fall back to prefs. Keys: `pw_<hostId>` for passwords, `pp_<keyId>` for key passphrases, `sync_passphrase` for the optional sync passphrase. SSH certificate paths are stored alongside `SshKeyEntry` (file paths, not secrets).
