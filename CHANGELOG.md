# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [0.1.22] — 2026-06-04

### Fixed
- **Windows local terminal keyboard input** — typing into the local PowerShell terminal did nothing (the prompt rendered but no keystroke ever reached the shell). Root cause is an upstream `flutter_pty` bug ([TerminalStudio/flutter_pty#19](https://github.com/TerminalStudio/flutter_pty/issues/19)): the Dart side puts the executable at `argv[0]` (Unix convention) and the Windows C side appends *all* arguments to the `CreateProcessW` command line, so the app actually spawned `powershell.exe powershell.exe` — PowerShell parsed the duplicate as `-Command` and ran a nested shell that never received ConPTY input. `flutter_pty` is now vendored as a local fork (`packages/flutter_pty`, `0.4.2+yourssh.1`) with `build_command` fixed to skip `argv[0]`.
- **Local terminal focus** — the local terminal now autofocuses when opened (matching SSH session tabs) instead of requiring a click before keystrokes register.
- **SFTP downloads of zero-size / growing files** — the size-bounded download loop exited immediately for files whose stat reports size 0 (procfs, FIFOs), producing empty files, and silently truncated files that grew mid-transfer. Downloads now read to EOF after the stat'd size is consumed, while still bounding in-size reads so servers that answer past-EOF reads with `SSH_FX_FAILURE` finish cleanly (a `FAILURE` after the stat'd size is treated as EOF).
- **Recursive download of symlinked directories** — `downloadDirectory` used raw lstat attrs while the panel listing resolves symlink targets, so a symlink-to-directory shown as a folder was downloaded as a file (failing with `SSH_FX_FAILURE`). Both paths now share the same symlink resolution.
- **Windows "Open with" discovery** — the OpenWithList registry query passed `-Ext` after a `-Command` script string, which PowerShell never binds to `param()`; the non-PATH exe scan used the `HKCR:` PSDrive, which does not exist by default in `powershell.exe`. The extension is now validated against a conservative charset (remote filenames are untrusted) and interpolated directly, the registry scan uses the provider-qualified `Registry::HKEY_CLASSES_ROOT` path, single quotes in exe paths are doubled for PS literals, and per-app description lookups run concurrently instead of one PowerShell spawn at a time.
- **Snippet "Sent" feedback for dead shells** — `SshService.sendInput` silently no-op'd when the session's shell was already gone, so snippets and plugins showed success for input that never reached the server. It now reports the failure (`PluginSSHException: Session has no open shell`).

### Changed
- **Linux app discovery** — `.desktop` files are read with async I/O instead of `readAsLinesSync` on the UI isolate.
- **Snippet search** — the label/command/tag filter is now a single shared helper (`filterSnippets`) used by both the Snippets screen and the terminal snippets panel.
- **External-edit upload toasts (SFTP)** — upload callbacks are wired once per panel and resolve the messenger at fire time, instead of capturing it per open (the mtime watcher fires long after the triggering open).
- **Injection gate** — sentinel scans resume from the previous buffer tail instead of rescanning the whole held buffer on every output chunk.

---

## [0.1.21] — 2026-06-03

### Changed
- **Invisible shell-integration setup** — the OSC 7/133 hook-installer script is no longer visible in the terminal when a session connects. The app now waits until the shell's line editor is actually reading input (bracketed-paste signal, with a gentle Enter-probe fallback for older bash) before delivering the script through a silent two-phase handshake: a short bootstrap line blocks in `read -rs` (tty echo disabled), the real script is consumed without ever being echoed, and the bootstrap's own echo is discarded client-side before it is ever painted — connecting just looks like an extra Enter press. If readiness can't be confirmed (exotic shells, full-screen apps, the user already typing) the injection is skipped entirely. Session recordings no longer capture the setup script either.

### Added
- **Terminal snippets panel** — a collapsible right-side panel inside the terminal workspace (toggled from the terminal toolbar) to browse, search, copy, and run saved snippets against the currently active pane without leaving the terminal screen.
- **Insert snippet into terminal** — the Snippets screen can now type a snippet directly into the focused session via the new plugin `sendInput` API (`YourSSHPluginContext.activeSession` + `sendInput`).
- **SFTP View mode** — right-clicking (or double-clicking) a file in the SFTP panel now shows separate **View** (read-only preview, lock icon in the AppBar, no save) and **Edit** (existing editable mode) actions so you can open log files and config files without risking accidental edits.
- **Open with… (SFTP)** — replaces "Open with external app" with an **Open with ▶** submenu that **opens on hover** (native cascading menu) and lists every application installed on your machine that can open the file's type (macOS via `NSWorkspace`/`LSCopyApplicationURLsForURL`, Linux via XDG MIME + `.desktop` files, Windows via registry). A **Choose…** option lets you pick any application with the OS file picker. The selected app is launched with the downloaded file and yourssh watches for saves and uploads changes back automatically.

### Fixed
- **SFTP symlinked directories** — directory listings now `stat` symlinks (listdir attrs have lstat semantics), so symlinked directories like `/bin → usr/bin` navigate correctly instead of being treated as files; downloads no longer read past EOF (some servers answer past-EOF reads with `SSH_FX_FAILURE` instead of `SSH_FX_EOF`); SFTP read errors show an actionable message instead of a raw exception.

### Security
- **Update binary integrity** — `downloadAsset()` now verifies the SHA-256 digest from the GitHub Releases API `digest` field before handing the file to the OS installer; a mismatch deletes the downloaded file and aborts the update. The HTTPS scheme check was tightened to use `Uri.tryParse` rather than a string prefix, so a malformed URL is caught as an `UpdateException` rather than a raw `FormatException`.

---

## [0.1.20] — 2026-06-03

### Added
- **Sudo SFTP (root file transfers)** — each host now has an **SFTP Mode** setting (Default / Sudo (root) / Custom command). In Sudo mode, yourssh starts the remote `sftp-server` through `sudo` over an exec channel (WinSCP-style) instead of the standard SFTP subsystem, so the entire SFTP session — browse, upload, download, rename, delete — runs as root. No more uploading to a temp dir and `sudo cp`-ing into place. It auto-detects the `sftp-server` path across distros (Debian/Ubuntu, RHEL/Fedora, Arch/SUSE), works with `NOPASSWD` sudoers entries, and otherwise prompts for the sudo password (validated separately via `sudo -S -v`, optionally remembered in the system keychain). Custom mode runs any server command verbatim (e.g. `sudo -u deploy …`). Failures surface a clear, actionable error (including a ready-to-paste `NOPASSWD` sudoers line) rather than silently falling back to a non-elevated session. A **root** badge marks elevated SFTP panels; terminal path autocomplete never triggers a sudo prompt.
- **Open with external app (SFTP)** — files the in-app editor cannot handle (binary formats, files over 5 MB) now offer to open with your OS default application instead; any file can also be opened externally from the SFTP context menu. While the file is open, yourssh watches the local copy and automatically uploads it back to the server every time the external app saves (WinSCP-style external editing).

### Fixed
- **SFTP file editing on Linux/Windows** — double-clicking a file in the SFTP panel no longer blanks the entire window on platforms where the embedded webview (Monaco) is unavailable. The editor now falls back to a plain-text editor with save support (`Ctrl+S`). ([#34](https://github.com/YoursshLabs/yourssh/issues/34))

---

## [0.1.19] — 2026-06-03

### Added
- **In-app updates (assisted download)** — yourssh now checks GitHub Releases for a newer stable version on launch (debounced to once per 24h) and on demand via a **Settings → Updates** button. When an update is available, a dismissible banner appears at the top of the app; choosing **Update** downloads the correct artifact for your OS/architecture and hands it to the OS installer (macOS strips the `com.apple.quarantine` flag and opens the DMG; Windows runs the installer `.exe`; Linux opens the `.deb`/`.tar.gz` with the desktop handler). If no artifact matches your platform (e.g. an Intel Mac) or a download/launch fails, it falls back to opening the Releases page in your browser. Because the app is not code-signed, this is an assisted flow — it never silently replaces itself.

---

## [0.1.18] — 2026-06-02

### Added
- **Shell integration (OSC 7 / OSC 133)** — yourssh now injects a small, guarded prompt-hook into bash/zsh sessions on connect (auto-on, opt-out per host and globally in **Settings → Terminal**) so it can read the remote shell's working directory and command boundaries via semantic-prompt escape sequences. This powers: the **working directory shown on the session tab** (e.g. `web-prod · app`), a **per-command status gutter** down the left of the terminal (green dot = exit 0, red = non-zero, grey = running), **jump-to-prompt** navigation (`Cmd/Ctrl+↑/↓` scrolls between command prompts), and **cwd-aware path autocomplete** in the command input bar (lists the resolved remote directory over SFTP). Sequences are captured via xterm's `onPrivateOSC` (no raw-stream parsing); non-bash/zsh shells and sessions where the markers are stripped simply see the feature stay inactive. The injected hooks affect only the live shell session — they never modify `.bashrc`/`.zshrc`.

---

## [0.1.17] — 2026-06-02

### Added
- **Connection health badge** — a live, latency-driven dot on each session tab: green (`<150ms`), amber (`150–500ms`), red (`>500ms` or unreachable), grey (connecting / no reading), with a pulsing amber dot during (re)connect. Hovering shows uptime, last-ping age, and the per-session reconnect count. A new `HealthMonitorService` pings each connected host over the live SSH channel (`SSHClient.ping`) on the keep-alive interval and becomes the sole pinger (the client's built-in keepalive is disabled), so a 5s ping timeout also surfaces half-open silent drops that the channel-close reconnect path cannot detect.

---

## [0.1.16] — 2026-06-01

### Changed
- **Cloud sync secret is now a 12-character sync code** — synced data is encrypted (AES-256-GCM) with a key derived from a random 12-char Crockford-Base32 code that is also the Supabase row id, replacing the anon-key-derived encryption and optional passphrase. The anon key is now only an API credential and can no longer decrypt anything. Generate a code on one device in **Settings → Sync** and enter it on your other devices to join — it is the only key to your data. Existing `default`-keyed rows are not migrated (fresh start); the old passphrase secret is removed on upgrade.

---

## [0.1.15] — 2026-06-01

### Fixed
- **Cloud sync rejected by Supabase `sync_data` policy** — the shipped client keys its row by the fixed id `default` (7 chars), but older deployments created `sync_data` with a `char_length(sync_id) = 12` CHECK (and a matching RLS `with check`) left over from an abandoned "sync code" design. Those constraints rejected every write (column CHECK → `23514`, RLS with-check → `42501`). The migration now drops the legacy constraint and relaxes the RLS policy to `with check (true)`; confidentiality still comes from client-side AES-GCM encryption of the payload. No-op on fresh installs.

---

## [0.1.14] — 2026-06-01

### Added
- **Advanced tab management** — rename tabs (double-click or right-click → Rename), color tags (8 preset colors shown as a dot), pin tabs (moves to front, hides close button, persists across reconnects), drag reorder (horizontal drag with pinned/unpinned zone boundary). All metadata persists per host via SharedPreferences (`TabMetadataService`).

### Fixed
- **Code editor: crash when opening an unreadable remote file** — opening a directory, a virtual/special file, or a file that hits a permission/IO error in the Monaco editor threw an unhandled `SftpStatusError` (SSH_FX_FAILURE, code 4) from the SFTP read and crashed the editor. `_loadFile` now catches the failure, shows the error in a SnackBar, and closes the editor instead of hanging on the loading spinner.

---

## [0.1.13] — 2026-06-01

### Added
- **Terminal sharing (multiplayer)** — host shares a live SSH session via a session code; guests join through the Command Palette ("Join Shared Session") or the `JoinShareDialog` and watch (or interact with) the terminal in real time. Built on Supabase Realtime channels; the host controls who can type via `targetGuestId`. A watch banner is shown in split-terminal view for guest sessions. Backed by `ShareSessionService`, `ShareProvider`, `ShareEvent`, and `ShareSessionDialog` / `JoinShareDialog`

### Fixed
- **Linux: missing `libkeybinder-3.0` at launch** — Ubuntu users without `libkeybinder-3.0-0` installed would get a shared-library crash on start. `libkeybinder-3.0.so.0` is now copied into the app bundle's `lib/` directory during cmake install, so no system package is required

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

[Unreleased]: https://github.com/YoursshLabs/yourssh/compare/v0.1.22...HEAD
[0.1.22]: https://github.com/YoursshLabs/yourssh/compare/v0.1.21...v0.1.22
[0.1.21]: https://github.com/YoursshLabs/yourssh/compare/v0.1.20...v0.1.21
[0.1.20]: https://github.com/YoursshLabs/yourssh/compare/v0.1.19...v0.1.20
[0.1.19]: https://github.com/YoursshLabs/yourssh/compare/v0.1.18...v0.1.19
[0.1.18]: https://github.com/YoursshLabs/yourssh/compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com/YoursshLabs/yourssh/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/YoursshLabs/yourssh/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/YoursshLabs/yourssh/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/YoursshLabs/yourssh/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/YoursshLabs/yourssh/compare/v0.1.12...v0.1.13
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
