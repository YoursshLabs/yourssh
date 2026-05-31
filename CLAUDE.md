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
- `packages/dartssh2` — **local fork** of dartssh2; overrides the pub.dev version via `dependency_overrides` in `app/pubspec.yaml`
- `packages/yourssh_plugin_api` — abstract plugin interface (`YourSSHPlugin`, `YourSSHPluginContext`)
- `packages/yourssh_devops` — DevOps plugin (network tools, Cloudflare tunnel, mail catcher, MCP server, S3 browser)
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
- `HostProvider` — CRUD for saved SSH hosts; fires `onMutation` callback to trigger sync push
- `SessionProvider` — manages active `SshSession` objects; wires key lookup, auto-reconnect, tmux, and host-key verification via callbacks set in `main.dart`
- `KeyProvider` — SSH key entries (path + optional passphrase + optional linked certificate path)
- `PortForwardProvider` — local/remote/dynamic `PortForward` tunnel configs (persistent rules)
- `TunnelProvider` — active `TunnelConfig` sessions (runtime state, separate from PortForwardProvider)
- `SnippetProvider` — reusable command snippets (managed by `yourssh_snippets` plugin)
- `SyncProvider` — holds Supabase sync config (URL/key, optional passphrase, status); `enabled` is derived from `isSupabaseConfigured` — no separate stored flag; passphrase stored in secure storage via `StorageService`
- `KnownHostsProvider` — persists known host fingerprints; exposes `pendingChallenge` for TOFU dialog
- `SettingsProvider` — app-wide prefs (auto-reconnect, tmux, hotkeys, feature flags for DevOps/WebTools/Snippets)
- `TerminalLayoutProvider` — split layout (none/horizontal/vertical) and input bar visibility
- `LocalSessionProvider` — manages local shell sessions via `flutter_pty`
- `LocalFilePanelProvider` — local filesystem state for the dual-panel SFTP view
- `SftpPanelProvider` — remote SFTP panel state (current path, directory listing)
- `SftpTransferProvider` — in-progress upload/download transfer queue and status
- `CommandHistoryProvider` — per-host command history for terminal autocomplete
- `AiChatProvider` — AI chat sidebar; supports multiple providers (`AiProvider` enum: `anthropic`, `openai`, `gemini`); API keys and model selection stored per-provider in `SharedPreferences`
- `PluginProvider` — activates/deactivates registered plugins; wraps `PluginContextImpl` for each
- `PluginEngineProvider` — wires `ScriptEngineService` into the Flutter state tree; surfaces loaded JS plugins, enabled state, and per-plugin console logs to the UI
- `RecordingProvider` — recording library state; `startRecording(session)` / `stopRecording(sessionId)`; `refreshLibrary()` scans disk for `.cast` files; `isRecording(sessionId)` for UI indicators; wired to `SessionProvider` via `recordingStart` callback in `main.dart`

**Services** (`app/lib/services/`):
- `SshService` — owns `SSHClient` and `SSHSession` maps keyed by host ID; handles connect, shell, exec, sftp, `testConnection` (TCP+auth without opening a shell), disconnect
- `StorageService` — host list as JSON in `SharedPreferences`; all secrets via `_saveSecret/_loadSecret/_deleteSecret` helpers (secure-first: write to `FlutterSecureStorage`, purge stale prefs copy on success, fall back to prefs on error); exposes `saveGenericSecret` / `loadGenericSecret` / `deleteGenericSecret` for app-scoped secrets (e.g., `sync_passphrase`)
- `CertificateKeyPair` — implements `SSHKeyPair`; wraps a PEM private key with a separate OpenSSH certificate file (base64 blob); used by `SshService` when `AuthType.certificate`
- `SyncService` — push/pull host data encrypted via `SyncEncryption` to a Supabase table; retries failed pushes every 30 s via timer; concurrent push while one is in-flight sets `sync_pending_push` instead of silently dropping the mutation; `disableAndDelete()` returns `String?` (remote delete error, or null on success) and calls `clearSupabaseConfig()` on the provider; `buildPayload` strips `detectedOs` from host JSON before upload
- `SupabaseService` — thin HTTP wrapper around Supabase REST API (upsert/fetch/delete a single row in `sync_data` table); raw `http` calls, no `supabase_flutter` SDK
- `P2PSyncService` — LAN sync via a one-shot HTTP server; `getLocalInterfaces()` enumerates non-loopback IPv4 interfaces with friendly `displayName` (Wi-Fi / Ethernet / VPN); `startServer(encryptedPayload, hostAddress)` binds on a random port and returns the full URL; server closes after the first successful `GET /sync` response; `onServerError` callback for mid-transfer errors; `fetchPayload(url)` HTTP GET with 5 s connect + 10 s body timeout
- `P2PSyncEncryption` — AES-256-GCM for LAN sync; `generateKey()` returns a random 32-byte key embedded in the QR URL (no PBKDF2 — key exchanged out-of-band via QR scan)
- `LocalShellService` / `PtyRunner` — local terminal via `flutter_pty`
- `HotkeyService` — global hotkey registration via `hotkey_manager`; hotkey names (`new_session`, `close_session`, `next_session`, `prev_session`, `toggle_input_bar`, `split_horizontal`, `split_vertical`) configured in `SettingsProvider`
- `SftpFileOpsService` — SFTP file operations (rename, delete, mkdir, permissions)
- `SftpTransferService` — chunked upload/download with progress callbacks
- `McpGatewayService` — starts a remote MCP server over SSH exec and forwards a local port to it
- `CloudflareTunnelService` — manages `cloudflared` tunnel process lifecycle
- `MailCatcherService` — connects to a remote MailCatcher SMTP instance via port forward
- `NetworkStatsService` — polls SSH exec to gather network interface stats for the overlay
- `NotificationService` — wraps `local_notifier` for desktop notifications
- `WebToolsService` — in-app HTTP requests through a port-forwarded connection
- `SystemAgentProxy` — proxies SSH agent socket for `AuthType.agent`
- `RecordingService` — writes asciicast v2 (`.cast`) files; tracks active recordings keyed by `sessionId`; passive intercept pattern — `SshService` always calls `writeOutput()` / `onShellClosed()`, which no-op when not recording

**Key models** (`app/lib/models/`):
- `Host` — connection profile (host, port, username, `AuthType`: `password` / `privateKey` / `certificate` / `agent`)
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

`YourSSHPluginContext` exposes: `activeSessions`, `execCommand(sessionId, cmd)`, namespaced `savePreference` / `getPreference`.

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
