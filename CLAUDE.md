# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Run on macOS (primary target)
cd app && flutter run -d macos

# Run on Windows
cd app && flutter run -d windows

# Build
cd app && flutter build macos
cd app && flutter build windows

# Lint / analyze
cd app && flutter analyze

# Tests
cd app && flutter test
cd app && flutter test test/services/sync_service_test.dart   # single test file
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

The active codebase is `app/` — a Flutter app targeting macOS and Windows. The `core/` Rust library is **not currently used at runtime**; it was built in Sprint 1 and kept for future `flutter_rust_bridge` integration.

**Monorepo layout:**
- `app/` — the Flutter app
- `packages/dartssh2` — **local fork** of dartssh2; overrides the pub.dev version via `dependency_overrides` in `app/pubspec.yaml`
- `packages/yourssh_plugin_api` — abstract plugin interface (`YourSSHPlugin`, `YourSSHPluginContext`)
- `packages/yourssh_devops` — DevOps plugin (network tools, Cloudflare tunnel, mail catcher, MCP server, S3 browser)
- `packages/yourssh_web_tools` — Web Tools plugin (in-app browser over port-forwarded HTTP)
- `packages/yourssh_snippets` — Snippets plugin

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
- `SyncProvider` — holds Supabase sync config (URL/key, enabled flag, status)
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

**Services** (`app/lib/services/`):
- `SshService` — owns `SSHClient` and `SSHSession` maps keyed by host ID; handles connect, shell, exec, sftp, `testConnection` (TCP+auth without opening a shell), disconnect
- `StorageService` — host list as JSON in `SharedPreferences`; passwords/passphrases in `FlutterSecureStorage` (`pw_<hostId>`, `pp_<keyId>`); falls back to `SharedPreferences` if secure storage fails
- `CertificateKeyPair` — implements `SSHKeyPair`; wraps a PEM private key with a separate OpenSSH certificate file (base64 blob); used by `SshService` when `AuthType.certificate`
- `SyncService` — push/pull host data encrypted via `SyncEncryption` (AES-256-GCM, key derived from Supabase anon key) to a Supabase table; retries failed pushes every 30 s via a timer
- `SupabaseService` — thin HTTP wrapper around Supabase REST API (upsert/fetch/delete a single row in `sync_data` table); raw `http` calls, no `supabase_flutter` SDK
- `P2PSyncService` — LAN sync via a one-shot HTTP server; exports an encrypted payload, shares URL as QR code for another device to import
- `P2PSyncEncryption` — AES-256-GCM encryption used by P2P sync
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

**Key models** (`app/lib/models/`):
- `Host` — connection profile (host, port, username, `AuthType`: `password` / `privateKey` / `certificate` / `agent`)
- `SshSession` — wraps an xterm `Terminal`; bridges `dartssh2` shell I/O to the widget; has `SessionStatus` (connecting/connected/disconnected/error) and reconnect attempt counter
- `SshKeyEntry` — key file path, optional passphrase, optional `certificatePath` for cert auth
- `PortForward`, `TunnelConfig`, `Snippet`, `KnownHost`, `NetworkStats`, `LocalEntry`, `SftpEntry`, `SftpTransferItem`
- `ChatMessage`, `AiProviderConfig` — AI chat models
- `ToolResult` — structured result from AI tool calls

**UI entry point:** `app/lib/main.dart` — instantiates services and long-lived providers, wires callbacks between them (key lookup, host-key verifier, sync-on-mutation), then mounts `MainScreen` under `MultiProvider`. The app is dark-only (`ThemeMode.dark`); theme constants live in `app/lib/theme/app_theme.dart` (`AppColors`).

**Navigation:** `MainScreen` (`app/lib/screens/main_screen.dart`) renders a top tab bar (pinned Home/SFTP + scrollable SSH session tabs) and a left sidebar. `NavSection` enum: `hosts`, `keychain`, `portForwarding`, `sftp`, `localTerminal`, `knownHosts`, `settings`, `plugins`. Each maps to a top-level screen widget under `app/lib/widgets/`.

**Code editor:** `CodeEditorScreen` renders a Monaco editor via `webview_flutter` using the bundled `assets/monaco_editor.html`.

## Plugin system

Plugins are compiled into the app (no dynamic loading). All registered plugins live in `app/lib/plugins/plugin_registry.dart` (`kRegisteredPlugins`). To add a plugin:
1. Add the package to `app/pubspec.yaml` dependencies
2. Import and instantiate in `plugin_registry.dart`

Each plugin implements `YourSSHPlugin` (from `yourssh_plugin_api`):
- `buildUI(context, pluginContext)` — returns the plugin's widget
- `onActivate(ctx)` / `onDeactivate()` — lifecycle hooks
- `minApiVersion` — checked at runtime against `kApiVersion`

`YourSSHPluginContext` gives plugins access to: `activeSessions`, `execCommand(sessionId, cmd)`, and namespaced `savePreference` / `getPreference`.

## Sync feature

**Supabase sync** (cloud): opt-in. Host data is AES-256-GCM encrypted (key = HKDF-SHA256 of the Supabase anon key) before upload. `SyncService.push` is triggered via `HostProvider.onMutation` on every host change and retried every 30 s on failure (`sync_pending_push` flag). `SyncService.pull` runs on `WindowFocus` and only applies if `remote.updated_at > last_push_at`.

**P2P sync** (LAN): `P2PSyncService` starts a one-shot HTTP server, encrypts the host list payload, and exposes a URL as a QR code. The receiving device scans the QR code and imports the encrypted payload.

## Credential storage

Passwords use a dual-write strategy: primary is `FlutterSecureStorage` (Keychain on macOS, Credential Manager on Windows); fallback read/write to `SharedPreferences`. Keys: `pw_<hostId>` for passwords, `pp_<keyId>` for key passphrases. SSH certificate paths are stored alongside `SshKeyEntry` (not in secure storage — they're file paths, not secrets).
