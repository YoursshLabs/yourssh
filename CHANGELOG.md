# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [0.1.12] — 2026-05-31

### Added
- **Docker / Kubernetes container browser** in the DevOps hub — lists running containers (`docker ps`) and pods (`kubectl get pods`) over an active SSH session, with a namespace field and an all-namespaces toggle for Kubernetes. An **Exec** action opens a new terminal tab that drops straight into the container/pod (`docker exec -it` / `kubectl exec -it`, with a bash→sh fallback; multi-container pods prompt for a container). When `docker`/`kubectl` is missing or unauthorized, an install/permission hint with a copy button is shown instead. Backed by a new `ContainerService` and an `initialCommand` threaded onto `SshSession` so the new shell runs the exec command on open

---

## [0.1.11] — 2026-05-31

### Added
- **Snippets plugin restored** — `SnippetProvider` is registered again (its absence was crashing the app), and the Plugin Manager now lists both built-in plugins (with enable/disable toggles) and loaded JS script plugins instead of showing only help text

### Fixed
- **Recordings screen crash on open** — opening the Recordings library threw `Cannot hit test a render box with no size` and the mouse-tracker `!_debugDuringDeviceUpdate` assertion. A `SizedBox(width: double.infinity)` used as a direct `Row` child resolved to an infinite width, leaving the row with no size; the library now renders the list directly when no recording is playing and only splits into a fixed-width list + player when one is

### Changed
- Moved the terminal **REC** (start/stop recording) button from the top-left to the top-right corner so it is easier to see

---

## [0.1.10] — 2026-05-31

### Added
- **Smart host filter** — the dashboard search box now parses a faceted query (`env:prod role:db region:sg`): values under the same tag key OR together, different keys AND together, and free-text terms match host label / address / username / tag values. Tags (`key:value`) are finally searchable. A row of toggleable suggestion chips above the host list builds the query with a tap

### Changed
- Internal refactor across `app/lib` (no behavior change): deduplicated helpers in `KeyProvider`, `KnownHostsProvider`, `AiChatProvider`, and `SftpTransferService`; replaced the 60-case hotkey `switch` with an O(1) `Map` lookup; precomputed search query and pinned-groups `Set` in the hosts dashboard to avoid per-frame work; guarded a redundant `notifyListeners()` in `LocalFilePanelProvider`
- Split large widgets for readability: extracted `_LocalEntryRow` from `LocalFilePanel`'s list builder, and split the sync settings section into `_buildCloudTab` / `_buildP2pTab` with a shared field-decoration helper

---

## [0.1.9] — 2026-05-31

### Changed
- Release pipeline expanded to build for all supported architectures: macOS arm64, x86_64, and universal binary; Windows x64 and arm64; Linux x86_64 and arm64

---

## [0.1.8] — 2026-05-31

### Added
- **Script Engine Plugin System** — QuickJS-based JS runtime; plugins load from `~/.yourssh/plugins/` at runtime without rebuilding the app; hot-reload on file save
- **Plugin manifest** (`plugin.json`) with permission model; user approves permissions per-plugin via consent dialog
- **HookBus** — event bus for terminal.output (transform), terminal.input (intercept/cancel), session.connect/disconnect, session.connect.before (cancel), command.before (modify/cancel), command.after (observe)
- **Bridge APIs** available to plugins: `ssh.sessions()`, `ssh.inject(sessionId, text)`, `storage.get/set/delete`, `ui.notify()`, `ui.statusbar.add/update/remove`, `ui.panel.register()`, `ui.clipboard.copy()`, `ui.addCommand()`, `console.log/warn/error`
- **Native panel messages** from plugin WebView HTML: `ssh-exec`, `ssh-sessions`, `sftp-list`, `sftp-read` — handled async in Dart, enables SSH/SFTP from panel HTML without JS async limitations
- **ScriptPluginPanelScreen** — WebView renderer for plugin panels with bidirectional JS↔Dart bridge
- **PluginLoader** — disk scan + DirectoryWatcher for hot-reload; permission consent dialog on first install
- **BundledPluginInstaller** — ships bundled plugins in app assets, installs to `~/.yourssh/plugins/` on first run
- **Snippets plugin migrated to JS** — compiled `yourssh_snippets` replaced by `dev.yourssh.snippets` JS plugin bundled in assets; data migrated from old SharedPreferences key automatically
- **Plugin Console** — per-plugin log viewer (Settings → Script Plugins) showing `console.log` output and errors
- **Plugin Manager screen** — shows pending consent, plugin directory info
- **Plugin Authoring Guide** (`docs/plugin-authoring-guide.md`) — A-Z guide for writing plugins: manifest, hook API, bridge API, native panel messages, examples, debugging, known limitations

### Changed
- `SshService` now accepts optional `HookBus` for terminal data interception
- `SshService.exec()` fires `command.before` (interceptable) and `command.after` (observe) hooks
- `SshService.connect()` fires `session.connect.before` (interceptable) hook
- `SshBridgeDelegate` extended with `sendInput(sessionId, text)` for terminal injection

### Removed
- `yourssh_snippets` compiled Dart plugin (replaced by bundled JS plugin)

---

## [0.1.7] — 2026-05-31

### Added
- **Command Palette** (Cmd/Ctrl+K) — fuzzy search over all app actions with keyboard navigation and match highlighting
- **Jump Host (SSH proxy)** — chain through a bastion host to reach targets behind firewalls; configurable per host profile
- `command_palette` hotkey wired to `SettingsProvider`
- Search-in-scrollback (`Cmd/Ctrl+F`): regex support, case-insensitive, prev/next navigation, match count, highlights via xterm TerminalController
- Workspace persistence: auto-reconnects open SSH tabs on relaunch with saved layout; warns if hosts no longer exist

### Changed
- Sync encryption upgraded to per-row random salt + optional user passphrase (PBKDF2-HMAC-SHA256, 100k iterations, AES-256-GCM); legacy rows auto-migrate on next write

### Fixed
- Closed TOFU bypass, escaped shell args, hardened credential storage
- Surfaced previously-silent errors; added `AppSnack` helper for in-app error display
- S3: SigV4 path/copy-source encoding; uploads now streamed
- WebTools: restricted WebView to `http(s)`, added request timeouts
- DevOps: required URL token; RFC 6266-encoded filename in LAN share
- Providers: defensive JSON parsing, immutable getters, throttled `notifyListeners`
- Models: tolerant JSON, no-leak terminal, TOFU challenge timeout, async `stat`
- SSH: idempotent dispose, `_safeNotify` throughout; extracted identity resolution
- Plugin lifecycle, `execCommand`, scoped pref namespace now correctly wired
- Jump client disconnected on session close; agent auth added to `testConnection` jump path

### Performance
- Eliminated main-screen rebuild loop; deduplicated `SessionProvider` watches
- SFTP transfers streamed; command-history writes debounced; small race fixes

---

## [0.1.5] — 2026-05-30

### Added
- **Session recording** — automatic or manual asciicast v2 (`.cast`) file recording per SSH session
  - `RecordingService` writes files to a configurable path; `RecordingProvider` manages library state
  - REC button overlay and red-dot indicator on session tabs during active recording
  - Auto-record toggle per host profile
  - Recording Library screen with in-app asciicast playback (`RecordingPlayerWidget`)
  - Recording path preference in Settings
- **SSH certificate authentication** — `AuthType.certificate`; `CertificateKeyPair` pairs a PEM private key with an OpenSSH CA-signed certificate; UI in KeychainScreen and AddHostDialog
- **Windows OpenSSH agent** — auto-connects to the Windows OpenSSH agent via named pipe (`\\.\pipe\openssh-ssh-agent`) using kernel32 FFI; `_WindowsPipeTransport` + `_AgentTransport` abstraction
- SFTP file editing — Edit option in context menu; `createFile` in `SftpFileOpsService`; Monaco editor gains dirty-tracking and unsaved-changes dialog
- New File button in SFTP panel toolbar

### Fixed
- Mounted guards added to `RecordingPlayerWidget` and `RecordingLibraryScreen`
- Optimistic locking in `startRecording`; delete errors propagated in `RecordingProvider`
- IO exceptions and sink leak in `RecordingService.startRecording`
- Fallback path in `SettingsProvider` when `HOME` env var is unset

---

## [0.1.4] — 2026-05-30

### Added
- **OS detection** — detects remote OS via `uname` after SSH connect; shows OS-specific SVG icon on host cards; `detectedOs` field on `Host` model
- **P2P LAN sync** — exports encrypted host payload as QR code; receiving device scans and imports; `P2PSyncService` (one-shot HTTP server) + `P2PSyncEncryption` (AES-256-GCM)
- **Desktop notifications** — `NotificationService` detects shell prompts and command completion; configurable per-session toggle in Settings
- **CSV host import** — RFC 4180 quoting, row-level warnings; wired into import panel UI
- **SSH agent auth** (`AuthType.agent`) — `SystemAgentProxy` proxies `SSH_AUTH_SOCK`; agent kept alive during auth
- **AI chat multi-provider** — supports Anthropic, OpenAI, and Gemini; provider picker in chat sidebar; API keys per-provider in Settings; `AiProvider` enum + `AiProviderConfig` model
- **Plugin system** — `yourssh_plugin_api` package defines `YourSSHPlugin` / `YourSSHPluginContext`; `yourssh_devops`, `yourssh_web_tools`, `yourssh_snippets` plugins registered at build time; Plugin Marketplace screen; `PluginProvider` manages lifecycle
- S3 browser and LAN Share moved into `yourssh_devops` package
- WebTools screens moved into `yourssh_web_tools` package
- QR export shortcut added to HostListPanel toolbar
- P2P Transfer section in SyncSettingsScreen; unified Cloud/P2P tab selector
- HTTP client enhancements (query params, auth, body types, history, improved UX)
- Dynamic version display; SFTP close button; settings polish

### Fixed
- Duplicate `_showQrExport` method removed; leftover P2P section cleaned up
- Removed duplicate `qr_flutter` entry from pubspec
- Agent proxy kept alive during auth; cleaned up on `connect()` failure
- `firstOrNull` used in certificate key picker validator
- Network client entitlement added to fix outgoing connections in production build
- Typed exception catches, reset processing on success, `await _startServer`

### CI
- PR test workflow added: runs `flutter analyze` + `flutter test` on every pull request

---

## [0.1.2] — 2026-05-30

### Added
- **35 terminal color theme presets** — visual picker in Settings; covers popular themes (Dracula, Solarized, Nord, One Dark, and more)

---

## [0.1.1] — 2026-05-30

### Added
- **Linux support** — builds and releases for Linux desktop
- MIT License

### CI
- Added `libkeybinder-3.0-dev`, `libsecret-1-dev`, and `libjsoncpp-dev` to Linux build dependencies

---

## [0.1.0] — 2026-05-29

### Added
Initial release of YourSSH — a cross-platform SSH client for macOS, Windows, and Linux.

- **SSH connections** — password, private key, and agent authentication; multi-session tabbed interface
- **Test Connection** — TCP + auth verification without opening a shell
- **Split terminal** — horizontal / vertical / quad layouts with session broadcast
- **Terminal input bar** — command history navigation, Tab completion, suggestion popup with arrow-key selection
- **Shell autocomplete** — keystroke-tracked overlay with per-session history (`CommandHistoryProvider`)
- **SFTP dual-panel** — directory navigation, file listing, checkbox selection, context menu, folder transfer, progress dialog, 3-column layout with remote-B panel
- **SFTP file ops** — rename, delete, mkdir, permissions (`SftpFileOpsService`)
- **Monaco code editor** — in-app editor for remote file editing via SFTP; bundled `assets/monaco_editor.html`
- **Local terminal** — built-in local shell via `flutter_pty`; multi-tab support
- **tmux integration** — optional tmux attachment per session
- **Network stats overlay** — Rx/Tx per-second display via remote `/proc/net/dev` polling
- **Multi-window** — launch additional app windows via new process
- **Global hotkeys** — configurable shortcuts (new session, close, next/prev, split, toggle input bar) via `hotkey_manager`
- **Supabase cloud sync** — AES-256-GCM encrypted host-list sync to Supabase; push on mutation, pull on window focus; `SyncService` + `SupabaseService`
- **Credential storage** — secure-first strategy: Keychain (macOS) / Credential Manager (Windows), fallback to `SharedPreferences`
- **Host management** — CRUD for SSH host profiles with `StorageService`
- **Known hosts** — TOFU dialog for host-key verification; `KnownHostsProvider`

[Unreleased]: https://github.com/YoursshLabs/yourssh/compare/v0.1.12...HEAD
[0.1.12]: https://github.com/YoursshLabs/yourssh/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/YoursshLabs/yourssh/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/YoursshLabs/yourssh/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/YoursshLabs/yourssh/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/YoursshLabs/yourssh/compare/v0.1.5...v0.1.8
[0.1.5]: https://github.com/YoursshLabs/yourssh/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/YoursshLabs/yourssh/compare/v0.1.2...v0.1.4
[0.1.2]: https://github.com/YoursshLabs/yourssh/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/YoursshLabs/yourssh/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/YoursshLabs/yourssh/releases/tag/v0.1.0
