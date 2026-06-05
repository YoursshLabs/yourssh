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

## Makefile targets (Rust core — inactive/future)

```bash
make setup          # Install deps (Rust targets, xcodegen)
make core           # Build universal .a + Swift bindings
make swift-bindings # Regenerate Swift bindings only
make open           # Generate Xcode project and open it
make clean          # Remove Rust build artifacts + generated bindings
```

## Architecture

The active codebase is `app/` — a Flutter app targeting macOS, Windows, and Linux. The `core/` Rust library is **not currently used at runtime**; it was built in Sprint 1 and kept for future `flutter_rust_bridge` integration.

**Monorepo layout:**
- `app/` — the Flutter app
- `packages/dartssh2` — **local fork** of dartssh2; overrides the pub.dev version via `dependency_overrides` in `app/pubspec.yaml`; adds `signAsync()` for agent-backed auth and SSH agent forwarding (sends `auth-agent-req@openssh.com` on shell channels only — never exec; accepts server-opened `auth-agent@openssh.com` channels via `SSHClient.agentHandler`; a refused request is non-fatal and surfaces as `SSHSession.agentForwardingRefused`)
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
- `SessionProvider` — manages the unified `TerminalSession` tab list (SSH sessions **and** local PTY shells; `sessions` / `sshSessions` / `activeSshSession` accessors); wires key lookup, auto-reconnect, tmux, and host-key verification via callbacks set in `main.dart`; `onSessionDropped` callback fires when a session drops without a pending auto-reconnect (not on user-initiated close) — wired to the notification center; local shells go through the injected `LocalShellService` (`newLocalSession` / `restartLocalSession`; the `localShell` setter wires the service's PTY-exit notifications into the provider's notify)
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
- `UpdateProvider` — in-app update flow: launch check (debounced 24h via `last_update_check` in `SharedPreferences`) + manual check, semver compare, download progress, and install hand-off; `showBanner` derived from `status == available && version != dismissedVersion`; `dismiss()` persists per-version; surfaces state to `UpdateBanner` and the Settings Updates section
- `NotificationCenterProvider` — in-memory store behind the notification bell in the top tab bar (`NotificationBell` widget); `add()` dedupes via `AppNotification.dedupeKey` (`update:<version>`, `disconnect:<sessionId>`) and caps at 50 items; `markAllRead()` on panel open, `clearAll()` / `remove(id)`; fed in `main.dart` by an `UpdateProvider` listener (one update notification per version) and `SessionProvider.onSessionDropped`

**Services** (`app/lib/services/`):
- `SshService` — owns `SSHClient` and `SSHSession` maps keyed by host ID; handles connect, shell, exec, sftp, `testConnection` (TCP+auth without opening a shell), disconnect; `ensureClient(host)` returns the open client or auto-connects with stored credentials (evicts dead cached clients; resolves `Host.keyId` via the `defaultKeyLookup` callback, host keys via `defaultHostKeyVerifier`)
- `PortForwardService` — runtime engine for port-forward rules: starts/stops local (`ServerSocket` → `forwardLocal` pipe), remote (`forwardRemote` → local socket pipe), and dynamic SOCKS5 (`forwardDynamic`) tunnels over a `TunnelTransport` abstraction (`SshTunnelTransport` wraps `SSHClient`; fakes in tests); watches `client.done` per host and auto-reconnects with exponential backoff (2 s doubling, 30 s cap; local listeners stay bound across drops); in-flight dials deduped per host; pushes state via `onStatus`/`onConnections` callbacks into `PortForwardProvider`; `autoStartAll` runs after the provider's `ready` future; `stopForHost` wired to host deletion. Design: `docs/superpowers/specs/2026-06-05-port-forwarding-runtime-design.md`
- `StorageService` — host list as JSON in `SharedPreferences`; all secrets via `_saveSecret/_loadSecret/_deleteSecret` helpers (secure-first: write to `FlutterSecureStorage`, purge stale prefs copy on success, fall back to prefs on error); exposes `saveGenericSecret` / `loadGenericSecret` / `deleteGenericSecret` for app-scoped secrets (e.g., `sync_passphrase`)
- `CertificateKeyPair` — implements `SSHKeyPair`; wraps a PEM private key with a separate OpenSSH certificate file (base64 blob); used by `SshService` when `AuthType.certificate`
- `SyncService` — push/pull host data encrypted via `SyncEncryption` to a Supabase table; retries failed pushes every 30 s via timer; concurrent push while one is in-flight sets `sync_pending_push` instead of silently dropping the mutation; `disableAndDelete()` returns `String?` (remote delete error, or null on success) and calls `clearSupabaseConfig()` on the provider; `buildPayload` strips `detectedOs` from host JSON before upload
- `SupabaseService` — thin HTTP wrapper around Supabase REST API (upsert/fetch/delete a single row in `sync_data` table); raw `http` calls, no `supabase_flutter` SDK
- `P2PSyncService` — LAN sync via a one-shot HTTP server; `getLocalInterfaces()` enumerates non-loopback IPv4 interfaces with friendly `displayName` (Wi-Fi / Ethernet / VPN); `startServer(encryptedPayload, hostAddress)` binds on a random port and returns the full URL; server closes after the first successful `GET /sync` response; `onServerError` callback for mid-transfer errors; `fetchPayload(url)` HTTP GET with 5 s connect + 10 s body timeout
- `P2PSyncEncryption` — AES-256-GCM for LAN sync; `generateKey()` returns a random 32-byte key embedded in the QR URL (no PBKDF2 — key exchanged out-of-band via QR scan)
- `LocalShellService` / `PtyRunner` — local terminal via `flutter_pty`
- `HotkeyService` — app hotkey registration via `hotkey_manager` with `HotKeyScope.inapp` (system scope used keybinder/XGrabKey on Linux — dead on Wayland, stole combos system-wide elsewhere; issue #46); hotkey names (`new_session`, `close_session`, `next_session`, `prev_session`, `toggle_input_bar`, `split_horizontal`, `split_vertical`, `command_palette`) configured in `SettingsProvider`; `shouldSwallowKeyEvent` lets terminal views drop a combo that already fired as a hotkey so it never reaches the shell
- `SftpFileOpsService` — SFTP file operations (rename, delete, mkdir, permissions)
- `SftpTransferService` — chunked upload/download with progress callbacks
- `ExternalEditService` — "open with external app" for SFTP files: downloads to a per-session temp dir, launches the OS default app (`url_launcher`) or a specific app (`openExternalWith`), polls mtime every 2 s and auto-uploads changes back to the server; `sftp_file_inspector.dart` (pure) decides which files the in-app editor refuses (binary extension, > 5 MB, null byte in first 8 KB)
- `AppDiscoveryService` — discovers installed applications for a given file path, filtered by MIME type; per-extension cache; macOS uses `LSCopyApplicationURLsForURL` via a `yourssh/app_discovery` Flutter method channel registered in `MainFlutterWindow.awakeFromNib` (NOT AppDelegate — its lifecycle overrides never fire in this app), Linux parses XDG `.desktop` files in Dart, Windows uses PowerShell registry queries
- `McpGatewayService` — starts a remote MCP server over SSH exec and forwards a local port to it
- `CloudflareTunnelService` — manages `cloudflared` tunnel process lifecycle
- `MailCatcherService` — connects to a remote MailCatcher SMTP instance via port forward
- `NetworkStatsService` — polls SSH exec to gather network interface stats for the overlay
- `NotificationService` — wraps `local_notifier` for desktop notifications
- `WebToolsService` — in-app HTTP requests through a port-forwarded connection
- `SystemAgentProxy` — proxies SSH agent socket for `AuthType.agent`; `roundtrip(bytes)` raw passthrough (frame/unframe only, payload never parsed) used by agent forwarding
- `AgentForwardingHandler` — serves forwarded `auth-agent@openssh.com` channels when `Host.agentForwarding` is on: relays each request verbatim over a fresh `SystemAgentProxy` connection (connection-per-request — agent protocol is serial per connection), falling back to a memoized `SSHKeyPairAgent` built from app-Keychain keys (`loadKeychainKeyPairs`; loader wired from `KeyProvider` + stored passphrases in `main.dart` via `SshService.keychainIdentitiesLoader`) only when the agent connect fails; attached to the destination client only in `SshService.connect` (never jump clients or `testConnection` — ProxyJump semantics); a server refusal prints a yellow warning in the terminal and the session continues. `loadKeyPairsFromFile` is the shared PEM+passphrase loader also used by `_resolveIdentities`
- `RecordingService` — writes asciicast v2 (`.cast`) files; tracks active recordings keyed by `sessionId`; passive intercept pattern — `SshService` always calls `writeOutput()` / `onShellClosed()`, which no-op when not recording
- `ShellIntegrationService` — pure (no Flutter/IO): `parseOsc(code, args)` maps xterm `onPrivateOSC` to a typed `ShellOscEvent` (OSC 7 cwd, OSC 133 A/D; C ignored); `buildInjectionScript()` is the guarded one-line bash/zsh prompt-hook installer (auto-on, opt-out via `Host.shellIntegration` + `SettingsProvider.shellIntegrationEnabled`), delivered **invisibly** via a two-phase handshake: `buildBootstrapLine()` (short line that disables tty echo and blocks in `read -rs`, printing `__YS_RDY__`/`__YS_DONE__` sentinels) + `buildPayloadLine()` (the installer, consumed by `read` so never echoed). `SshService.openShell` wires `terminal.onPrivateOSC` and injects only when `injection_gate.dart`'s `InjectionReadiness` confirms the line editor is reading (bracketed-paste `ESC[?2004h` toggle + settle, bare-`\n` probe fallback for bash ≤ 5.0; skipped on alt-screen/user typing/never-confirmed) while `InjectionGate` withholds and discards the bootstrap echo; `path_completion.dart` (pure) plans cwd-aware path completion for the input bar over `SshService.listDirectory`. Design: `docs/superpowers/specs/2026-06-03-invisible-shell-integration-design.md`
- `UpdateService` — in-app update glue: `fetchLatestRelease()` (GitHub `releases/latest`, stable-only), pure `isNewerVersion` (semver, fail-closed on blank) and `assetForPlatform` (OS/arch → release asset; macOS arm64-only → null on Intel), `downloadAsset` (streamed to Downloads with progress, cleans up partial file), `launchInstaller` (macOS: strip `com.apple.quarantine` + `open` DMG; Windows: run installer `.exe`; Linux: `xdg-open`); throws typed `UpdateException`; takes an injectable `http.Client` for testing

**Key models** (`app/lib/models/`):
- `Host` — connection profile (host, port, username, `AuthType`: `password` / `privateKey` / `certificate` / `agent`; `agentForwarding` opt-in per host, default off)
- `SshSession` — wraps an xterm `Terminal`; bridges `dartssh2` shell I/O to the widget; has `SessionStatus` (connecting/connected/disconnected/error) and reconnect attempt counter
- `SshKeyEntry` — key file path, optional passphrase, optional `certificatePath` for cert auth
- `PortForward`, `TunnelConfig`, `Snippet`, `KnownHost`, `NetworkStats`, `LocalEntry`, `SftpEntry`, `SftpTransferItem`
- `ChatMessage`, `AiProviderConfig` — AI chat models
- `ToolResult` — structured result from AI tool calls
- `RecordingEntry` — immutable metadata for one `.cast` file; `hostTitle` and `recordedAt` parsed from path (`{basePath}/{user}@{host}/session_YYYY-MM-DD_HH-mm-ss.cast`)

**UI entry point:** `app/lib/main.dart` — instantiates services and long-lived providers, wires callbacks between them (key lookup, host-key verifier, sync-on-mutation), then mounts `MainScreen` under `MultiProvider`. The app is dark-only (`ThemeMode.dark`); theme constants live in `app/lib/theme/app_theme.dart` (`AppColors`).

**Navigation:** `MainScreen` (`app/lib/screens/main_screen.dart`) renders a top tab bar (pinned Home/SFTP + scrollable SSH session tabs) and a left sidebar. `NavSection` enum: `hosts`, `keychain`, `portForwarding`, `sftp`, `localTerminal`, `knownHosts`, `recordings`, `settings`, `plugins`. Each maps to a top-level screen widget under `app/lib/widgets/`.

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
