# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Scrollback paging keys** — Shift+PageUp / Shift+PageDown page through the terminal scrollback (main buffer only; alternate-screen apps still receive the keys)
- **Reset Terminal** — right-click action that recovers a session stuck in the alternate screen with mouse reporting left on (full-screen app crashed / SSH dropped mid-TUI): returns to the main buffer, disables mouse mode, re-shows the cursor — the local equivalent of `reset`

### Changed
- **Terminal render performance** — visible lines are painted via cached per-line pictures re-recorded only when a line's content changes (new `BufferLine.version`), turning a steady frame from O(visible cells) paragraph draws into O(visible lines) picture replays (~7× less per-frame paint work); keyword-highlight regexes now run on line change instead of every frame

### Fixed
- **Mouse wheel inside mouse-aware TUIs** (#65) — wheel up/down were reported with button codes 68/69 instead of the standard 64/65, so claude CLI, htop, `vim mouse=a`, lazygit, and tmux (mouse on) ignored every wheel event; legacy-mode reports also placed events one row below the pointer
- **Scrollback drift at the cap** (#66) — once the buffer hit `maxLines`, content a scrolled-up reader was viewing streamed past as lines were trimmed from the top; the viewport now compensates for trimmed lines and stays pinned to the text
- **Decomposed (NFD) Vietnamese text** (#67) — combining marks are now canonically composed into the preceding cell (every Vietnamese letter has a precomposed form), so macOS `ls` filenames and other NFD sources render correctly instead of one displaced cell per diacritic

---

## [0.1.35] — 2026-06-11

### Added
- **Breadcrumb path jump** — the shared `PathBreadcrumb` gains an inline path editor: an edit affordance opens a text field seeded with the current path; Enter navigates there, Escape cancels. Wired into both the remote SFTP panel and the local file panel; remote-typed paths are normalized to absolute POSIX (trailing slash dropped) so derived child paths don't double up
- **macOS universal build** — Intel Macs are now supported: one universal (arm64 + x86_64) artifact (`YourSSH-x.x.x-macOS-universal.dmg/zip`) built on the arm64 runner; `build.sh` lipos both Rust dylib targets and the release workflow asserts both arches via `lipo -archs` so an arm64-only artifact can never ship under the universal name; the in-app updater matches the universal DMG on both archs (Intel falls back to the browser against pre-universal releases)

### Changed
- **Performance pass** — compiled keyword-highlight rules are memoized in `SettingsProvider` (previously every terminal build recompiled each rule's RegExp, duplicated across three widgets); `SessionProvider.setActive` no longer notifies when re-clicking the already-active tab; SSH agent messages are built with a direct buffer write instead of double list spreads
- **Smaller bundles** — removed the unused `local_auth` dependency (pulled native plugins into macOS/Windows bundles); dropped the MesloLGS NF Italic / Bold Italic faces (−4.8 MB per bundle; the engine falls back to a synthetic slant); desktop release builds use `--split-debug-info`, with per-platform symbols zips attached to each release for `flutter symbolize`

### Fixed
- **Non-ASCII terminal input** — typed input was sent to the SSH shell via truncated UTF-16 code units, corrupting any character above U+00FF (e.g. Vietnamese: "ế" arrived as a single garbage byte). Input is now UTF-8 encoded at every user-text write site (keystroke/IME, `terminal.input` plugin hook, startup command, snippet insert), matching the local-shell path
- **Windows build on VS 2026** — unblocked the MSVC STL1011 coroutine error

---

## [0.1.34] — 2026-06-08

### Added
- **Kubernetes panel** — `KubernetesPanel` widget inside the DevOps plugin: context switcher, streamed `kubectl logs -f` in a scrollable sheet, and 1-click port-forward (`kubectl port-forward`) via `ContainerService.execStream`; namespace filter + all-namespaces toggle
- **`onOpenBrowser` DevOps callback** — `DevOpsPluginConfig` gains an `onOpenBrowser` callback so the host app can handle in-app browser navigation from DevOps tools without a hard dependency on the WebTools plugin
- **Keyword highlighting** — user-defined regex rules tint matching terminal output at paint time in the xterm fork; defaults ship with Error/Warning/Fail rules (red/yellow/cyan); toggle + rule list + add/edit dialog + color picker in Settings → Terminal and the terminal config side panel; rules persisted in `SettingsProvider`
- **Server monitor panel** — per-host live dashboard (CPU / memory / disk / uptime / listening ports / firewall status) in a draggable bottom sheet; access from the host card hover button or right-click context menu; `SystemStatsService` polls every 5 s via a single compound SSH exec with sentinel markers; `FirewallStatusService` polls every 30 s and auto-detects ufw / iptables / nftables; requires an active SSH session
- **Network discovery** — scan the local network for SSH/RDP hosts without typing an IP; `NetworkDiscoveryService` combines mDNS (`_ssh._tcp`, `_rdp._tcp`) and a configurable TCP port scan on the local subnet; results appear in a bottom sheet with one-tap **Add Host**; also reachable from a **Scan network** link in the Add Host panel
- **Import sources expansion** — nine import sources with a source-picker grid UI; five new formats alongside the existing SSH config / JSON / CSV:
  - **PuTTY** `.reg` registry export (hex port decoding, URL-decoded session names)
  - **MobaXterm** `.mxtsessions` (SSH sessions only, type `0`; handles multi-section `[Bookmarks_N]` files)
  - **SecureCRT** XML session files (recursive folder traversal → group path)
  - **Ansible** INI inventory (`ansible_host`, `ansible_user` / `ansible_ssh_user`, `ansible_port` with validation; `:vars` and `:children` sections skipped)
  - **WinSCP** `.ini` session export (URL-decoded names, nested path → label + group)
  - **Termius** JSON export (`address` → host, `group.label` → group; falls back to YourSSH JSON format)
  - **SSH URI** — one `ssh://user@host:port` per line
- **Known hosts import** — import `~/.ssh/known_hosts` into the app's known-hosts store via an IMPORT button on the Known Hosts screen; skips duplicates (host:port:keyType) and hashed entries; fingerprints computed as MD5(key\_blob) to match what dartssh2 passes to the host-key verifier

### Fixed
- Server monitor panel: disk mount-point labels showed raw inode-count numbers on macOS servers — fixed by using `df -Pk` (POSIX output format) instead of `df -k`
- Server monitor panel: polling services now guard against overlapping exec calls (in-flight guard); errors surface in the sheet instead of showing an infinite spinner
- Network discovery: silent error catches replaced with `debugPrint` logging; `_loadSubnets` now handles `NetworkInterface.list` failures gracefully; scan errors shown in the UI
- `DiscoveredHost.merge()` now preserves source when merging two hosts from the same discovery method

### Performance
- Dashboard sort memoization — `HostsDashboard` no longer re-sorts the full host list on every keystroke; added an `identical`-based memo (`_memoSortedHosts`) and a set-based selection cleanup; O(n log n) per build → amortized O(1) for unchanged inputs
- External-edit watcher deduplication — `ExternalEditService._startWatcher` cancels any existing watcher for the same (host, remote path) before creating a new one, preventing duplicate poll timers when a file is re-opened
- K8s port-forward log-line accumulation — `ContainerService.startPodPortForward` listener early-returns after `Forwarding from` is matched instead of accumulating all kubectl output indefinitely

---

## [0.1.33] — 2026-06-07

### Added
- **In-app RDP client** — connect to Windows, xrdp, and any RDP-compatible remote desktop server directly from a YourSSH tab alongside SSH sessions. Powered by [IronRDP](https://github.com/Devolutions/IronRDP) via `flutter_rust_bridge` v2.
  - NLA, TLS, and auto security modes
  - Optional SSH tunnel via a saved jump host (picks up the host's existing connection chain)
  - Server-certificate TOFU with **pre-auth pin enforcement**: first connect shows a trust dialog and pins the certificate; on later connects the pinned fingerprint is verified inside the Rust engine after the TLS handshake but **before CredSSP/NLA runs — a changed certificate aborts the connection without ever transmitting your credentials**, then offers a re-trust + reconnect flow; an already-trusted pin reconnects silently (no re-prompt)
  - Server-negotiated resolutions handled: the requested size follows the window, and if the server overrides it the framebuffer adapts instead of corrupting
  - **Fullscreen mode** — toolbar button takes the remote desktop truly fullscreen (OS window fullscreen, all app chrome hidden); an mstsc-style pill revealed by hovering the top screen edge offers Ctrl+Alt+Del / clipboard / exit / disconnect, and the session drops back to windowed automatically if it disconnects or you switch tabs
  - Full keyboard support: all printable keys, Ctrl+Alt+Del toolbar button, function keys, arrows; app hotkey combos are swallowed so they don't also type into the remote desktop
  - Mouse: move (deduplicated), left/right/middle click, vertical + horizontal scroll with coordinate scaling on window resize
  - Bidirectional clipboard (copy from remote desktop, paste into it; focus-gain push skips unchanged content)
  - Host editor: SSH/RDP protocol selector, port auto-flip (22 ↔ 3389, custom ports preserved), domain field, security mode dropdown, SSH tunnel picker; editing an RDP host never downgrades it to SSH
  - RDP badge on host cards, list rows, and detail panel header; dashboard actions are protocol-aware (SFTP/Test/bulk-run hidden or filtered for RDP hosts)
  - Parity with SSH tabs: rename/color/pin persist, tabs restore on relaunch, connects/disconnects audited, unexpected drops reach the notification bell
  - Server-initiated session end (remote sign-out, another client taking over the session, admin disconnect) is detected from the MCS Disconnect Provider Ultimatum and shown as a clean "server ended the session (…)" disconnect with Retry — not a raw protocol error
  - Feature exclusions: recording, split view, input bar, and snippets panel are hidden/disabled for RDP tabs; hotkeys for those features no-op when an RDP tab is active
  - Deferred: audio redirection, drive/printer redirect, dynamic resize — out of scope for this release

### Removed
- Dead `AddHostDialog`/`HostListPanel` widgets (unreferenced legacy host editor) — `HostDetailPanel` is the single host editor and now owns the SSH/RDP protocol UI

---

## [0.1.32] — 2026-06-07

### Added
- **Multi-hop jump chain** — connect through multiple bastions
  (bastion → bastion → … → target) for layered networks. The Connection
  Chain editor now appends and removes hops (persistent **Add a Host**,
  per-hop remove, Clear), hosts already in the chain are excluded from the
  picker so loops can't be built, and every hop's host key is verified like
  a direct connection. Terminal, SFTP, exec, and port forwarding all tunnel
  through the full chain; clients are cached per chain prefix and torn down
  deepest-first. An existing single jump host migrates automatically and
  stays compatible with older app versions through sync.
- **Session template (per-host preset)** — per-host working directory and
  environment variables applied invisibly on connect via the
  shell-integration handshake, a startup snippet typed after setup (skipped
  under tmux and when the handshake aborts), and per-host terminal theme /
  font / size / TERM / tmux overrides that fall back to the global settings.
  New SESSION TEMPLATE section in the host panel with env-key validation.
- **Internal audit log** — local SQLite trail of connect / disconnect /
  exec / input events with per-caller source tagging (bulk runs, DevOps
  tools, plugins, input bar), secret redaction before insert, an Audit Log
  screen with type/time/search filters and keyset pagination, CSV/JSON
  export, and retention pruning (default 90 days, configurable). Writes are
  fail-soft and can never break an SSH operation.
- **In-app SSH key generation** — generate Ed25519 (pure Dart,
  interop-verified against `ssh-keygen`), RSA-4096, or ECDSA-P256 keys from
  the Keychain screen, with optional passphrase stored in secure storage.
  Copy the public key or deploy it to a host with the new ssh-copy-id-style
  dialog (idempotent — deploying twice never duplicates the line).
- **Local shell picker** — choose which shell local terminal tabs run:
  auto-detected per platform (Windows: PowerShell, cmd, PowerShell 7, Git
  Bash, one profile per WSL distro; macOS/Linux: `$SHELL` + `/etc/shells`)
  plus custom executables with arguments. Default in Settings → Terminal,
  per-session choice in the new-tab (+) menu.
- **Recording redaction** — passwords, tokens, and API keys are masked with
  `[REDACTED]` before terminal output is written to `.cast` recordings
  (same patterns as the audit log: `key=value` secrets, Bearer tokens,
  `sshpass -p`, mysql `-p`, `redis-cli -a`, URL passwords). On by default;
  global switch in Settings → Recording plus a per-host opt-out. Output is
  coalesced per line so secrets split across chunks are still caught — this
  also hides keystroke timing, a side-channel in shared recordings.

---

## [0.1.31] — 2026-06-06

Packaging-only release — no app code changes. Fixes install failures
reported on ARM64 that actually affected all architectures.

### Fixed
- **Windows portable build was unusable** — the previous
  `YourSSH-<ver>-Windows-<arch>.exe` asset was the bare `yourssh.exe`
  without `flutter_windows.dll`, the plugin DLLs, or `data/`, so it always
  failed at launch with a missing-DLL error. Replaced by
  `YourSSH-<ver>-Windows-<arch>-portable.zip` containing the full Release
  folder — extract and run.
- **Windows builds now bundle the VC++ runtime** (`msvcp140.dll`,
  `vcruntime140*.dll`) so the installer and portable ZIP work on fresh
  machines/VMs without the Visual C++ Redistributable — common on
  Windows-on-ARM.
- **Linux builds run on Ubuntu 22.04 / Debian 12 again** — release builds
  moved from Ubuntu 24.04 to 22.04 runners, lowering the glibc requirement
  from 2.38 to 2.35. Previously the app aborted at launch on anything older
  than Ubuntu 24.04 (including Raspberry Pi OS bookworm).

---

## [0.1.30] — 2026-06-06

### Added
- **Connection Chain editor** — the Jump Host dropdown in the host panel is
  now a visual chain (Termius-style): host cards connected by an arrow
  showing bastion → destination, a searchable **Add a Host** picker, a key
  icon on the bastion card when agent forwarding is enabled, and a **Clear**
  button for direct connections. Click the bastion card to swap hosts.
- `tool/jump_probe.dart` — layer-by-layer jump-host diagnostic CLI
  (TCP → bastion auth → direct-tcpip channel → target auth → exec) for
  debugging "can't reach host behind bastion" reports.
- **Bulk action panel** — select N hosts on the dashboard (SELECT mode with
  per-card checkboxes, filter-aware Select all, Esc to exit) and act on all
  of them at once:
  - **Connect all** — opens a tab per host, skips already-connected hosts,
    confirms before opening more than 5 tabs
  - **Run command** — one command (free text or snippet) executed in
    parallel (bounded concurrency, 30 s per-host timeout, per-host failure
    isolation); per-host results with exit code, duration, and expandable
    stdout/stderr; a **Diff** tab groups identical outputs against a
    baseline (any group can be promoted) and side-by-side compares any two
    hosts
  - **Push files** — upload files/folders to one remote path on every host
    (destination created if missing, existing files overwritten) with
    per-host byte progress and cancel
- Closing a bulk dialog mid-run asks for confirmation; queued hosts are
  cancelled while in-flight operations finish and record their real result
- **Grid & List view for the hosts dashboard** — toggle between the card
  grid and a compact single-line list; pick a sort order (name, creation
  date, or hostname, ascending/descending) from the new toolbar dropdown.
  Both choices persist across restarts. Default order is now Name A–Z
  (previously insertion order).
- **Agent forwarding observability** — live SSH agent status in the host
  panel (system agent / Keychain fallback / nothing detected), a
  per-session key icon on the session tab (ready / active / fallback /
  refused), and a notification-bell item with tap-to-jump when the server
  refuses forwarding.

### Fixed
- **Jump host on auto-connect paths** — SFTP, exec, and port forwarding
  auto-connect (`ensureClient`) never resolved the host's jump host, so
  hosts behind a bastion dialed direct and timed out. They now tunnel
  through the bastion exactly like interactive sessions.

### Changed
- Command-finish notifications are now **off by default** (re-enable via
  Settings → Monitoring); existing installs keep their saved choice
- `SftpTransferService.uploadFile` reports byte progress;
  `uploadDirectory` gained an `overwrite` flag (bulk push uses it — the
  SFTP panel's skip-existing behavior is unchanged)

---

## [0.1.29] — 2026-06-05

### Added
- Unified right-click context menu in both SFTP panels: Open, Open with…,
  Copy to target directory (disabled with a reason when it can't run — no
  target panel, folders between two remote hosts, or both panels showing
  the same folder), Refresh, New Folder, Edit Permissions, Rename, Delete
- **Edit Permissions (chmod)** — rwx checkbox grid two-way synced with a
  validated octal field (octal-only input, 3–4 digits, Apply disabled while
  the value is incomplete or invalid); directories get recursive apply with
  a hardened walk: entries whose listing omits the mode are classified via
  lstat, symlinks are never followed (SETSTAT would chmod the link target),
  a directory's own mode is applied after its contents, and file chmods run
  in batches of 8; unknown current permissions fall back to a stat() and
  then warn + gate Apply instead of silently offering `chmod 000`; the
  local panel uses the system `chmod` (macOS/Linux)
- Right-click context menu on port-forwarding rules: **Duplicate** (fresh
  id, "(copy)" label, auto-start off), Edit, Delete
- **Middle-click closes** unpinned session tabs (pinned tabs are protected)
- **Distro-level OS icons** — Linux hosts are identified via
  `/etc/os-release` and show their distro glyph (Ubuntu, Debian, Fedora,
  CentOS, Rocky, Alma, Alpine, Amazon, Arch, SUSE, Red Hat) on the hosts
  dashboard and SSH session tabs; hosts detected as generic Linux upgrade
  on their next connect
- **Update re-check while running** — the update check now also re-runs on
  a 6-hour timer and on window focus (same 24h debounce), so the
  notification bell picks up new releases without restarting the app

### Fixed
- Strict KEX (`kex-strict-c/s-v00@openssh.com`) in the bundled dartssh2
  fork — mitigates CVE-2023-48795 "Terrapin"
- Remote shells open at the terminal's real size instead of 80×24
- Terminal snippets entry points (toolbar button, side panel) are hidden
  when the Snippets plugin is disabled
- SFTP/local panels no longer touch a disposed widget when a slow
  operation (chmod, rename, delete, new folder) finishes after the tab
  was closed
- Local file listings carry the file mode from scan time — the permissions
  dialog no longer blocks the UI thread with a synchronous stat
- The terminal's AI chat toggle (and any open chat panel) is hidden until
  an AI provider API key is configured

### Changed
- Displayed branding strings now use yoursshlabs.com
- Settings: removed the redundant About section

---

## [0.1.28] — 2026-06-05

### Added
- SSH Agent Forwarding (per-host toggle, like `ssh -A`): forwarded agent
  channels are served by the local system agent (`SSH_AUTH_SOCK` / Windows
  OpenSSH agent pipe), falling back to keys stored in the app Keychain when
  no system agent is running. Forwarding is requested on shell sessions only
  (background exec commands skip the extra round-trip), and a server refusing
  the request shows a warning in the terminal instead of aborting the
  session. ([#49](https://github.com/YoursshLabs/yourssh/issues/49))

### Fixed
- Editing a host through the quick Edit dialog no longer silently resets the
  fields the dialog has no controls for — group, tags, auto-record, shell
  integration, jump host, detected OS, created date, and agent forwarding all
  survive the edit; switching auth away from a key still clears the linked
  key. ([#51](https://github.com/YoursshLabs/yourssh/issues/51))

---

## [0.1.27] — 2026-06-05

### Added
- **Port forwarding runtime** — saved rules can now actually start and stop. Local, remote, and dynamic (SOCKS5) tunnels run over the host's SSH connection (reusing an open one or auto-connecting with stored credentials — no terminal tab required), with auto-reconnect on dropped links (exponential backoff 2 s → 30 s, local listeners keep their port), an edit panel, an auto-start-on-launch flag, live per-tunnel connection counters, and inline error reporting (e.g. "Port 8080 already in use"). Active local forwards now appear in the Web Tools port-forward browser.

---

## [0.1.26] — 2026-06-05

### Added
- **Terminal appearance side panel** — the tune icon in the terminal toolbar opens a right-side panel to change the color theme, font size, and font family without leaving the workspace. The font-size slider previews live on every terminal while dragging and persists once on release. The panel shares its controls with Settings → Terminal and is mutually exclusive with the snippets panel (opening one closes the other); both panels now share a common frame.
- **Nine new terminal themes** (35 → 44) — Kanagawa Dragon, Kanagawa Lotus, Tokyo Night Day, Nord Light, Light Owl, Flexoki Dark, Flexoki Light, Aura, and Cyberpunk, sourced from their authors' published palettes and grouped next to their families in the picker. Cursor, selection, and search-hit colors on the light variants are tuned for visibility.

### Fixed
- A font size stored outside the slider's 10–24 pt range (e.g. hand-edited preferences) no longer crashes the appearance controls — the slider clamps the displayed value.

---

## [0.1.25] — 2026-06-04

### Added
- **Notification bell in the top tab bar** — a bell button with an unread badge opens an anchored popover listing in-app notifications: a new release being available (with an inline **Update** button that starts the download, plus a link to the full release notes in Settings → Updates) and sessions that drop unexpectedly (shell closed without a pending auto-reconnect, or reconnect attempts exhausted — user-initiated closes don't notify). Opening the panel marks everything read; items can be dismissed individually or cleared all at once. Notifications are in-memory only, capped at 50, and deduped per release version / per session.
- **Community health files** — `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, and GitHub issue templates (bug report, feature request, question).

---

## [0.1.24] — 2026-06-04

### Added
- **Local terminal as first-class tabs** — local shell sessions now live in the global top tab bar next to SSH sessions (unified `TerminalSession` model in `SessionProvider`), can be split into panes alongside SSH panes, support asciicast recording, and show a status overlay with a restart action when the shell exits.
- **SFTP two-panel layout with switchable sources** ([#41](https://github.com/YoursshLabs/yourssh/issues/41)) — each panel can browse Local or any saved host via a source chip; unified panel headers (source chip + filter + actions) and clickable breadcrumb navigation in the remote panel replace the single `Up` button.
- **Local panel checkboxes** — the local file panel gains per-row checkboxes and a select-all header with a selection count, matching the remote panel; select-all respects the active filter on both panels.
- **Docked transfer panel** — transfer progress moved from a blocking centered dialog to a minimizable panel docked at the bottom of the SFTP workspace. Transfers run in the background: the panels stay fully interactive, additional transfers queue onto the running batch, the panel collapses to a slim progress strip, successful batches auto-dismiss after ~3 s, and failed ones stay visible until closed.
- **Terminal right-click menu** — right-clicking an SSH or local terminal opens a Copy / Paste / Select All context menu (Copy is disabled when nothing is selected).

### Fixed
- **Copying from the terminal** ([#43](https://github.com/YoursshLabs/yourssh/issues/43)) — copy/paste was effectively unreachable on Windows/Linux: `Ctrl+C` always meant SIGINT, the only copy binding was the undiscoverable `Ctrl+Shift+C`, and the right/middle mouse buttons did nothing. The terminal now mirrors Windows Terminal behavior: `Ctrl+C` copies when a selection is active (and clears the selection, so the next `Ctrl+C` reaches the shell as SIGINT), and `Ctrl+Shift+V` joins `Ctrl+V` as a paste alias. macOS `Cmd+C`/`Cmd+V` are unchanged.
- **Middle-click paste** — middle-click now pastes the clipboard, the standard terminal-emulator gesture. The xterm fork routed middle clicks to the right-button callbacks (and reported them to mouse-mode apps as the right button); they now use their own path, and mouse-mode apps (vim, htop) receive a proper middle-button event instead.
- **Recording playback terminal** is now read-only, so clicks and paste gestures can no longer inject input into a replay.
- **SFTP workspace lost on tab switch** ([#42](https://github.com/YoursshLabs/yourssh/issues/42)) — `DualPanelSftpScreen` was disposed whenever another tab became active, dropping connected hosts, paths, listings and in-flight transfers; it is now kept alive offstage (`KeepAliveOffstage`) so returning to the SFTP tab resumes where you left off.
- **Unreadable terminal selection** ([#40](https://github.com/YoursshLabs/yourssh/issues/40)) — every bundled theme used a fully opaque selection color painted over the text layer, hiding selected text entirely; all themes now use xterm's semi-transparent default alpha (`0xAA`), guarded by a test.
- **Windows app icon** — the packaged Windows build shipped the default Flutter icon instead of the terminal logo.
- **Hotkeys on Linux** — app hotkeys (new/close/next/prev session, splits, input bar, command palette) are now registered in-app instead of as system-wide global hotkeys (#46). They work on Wayland, where keybinder/`XGrabKey` could never grab (startup logged `Binding '<Primary>t' failed!` and the keys silently did nothing), and they no longer steal their combos from every other application on X11/macOS/Windows while the app is running. Terminal views swallow a matching combo so a hotkey no longer also types its control sequence into the shell (e.g. Ctrl+T sending `^T`).
- **`split_vertical` default rebound** from `ctrl+shift+v` to `ctrl+shift+e` so it no longer shadows terminal paste on Windows/Linux (#43); saved settings still on the old default are migrated on load.
- **Pre-release review hardening** — a 9-angle adversarial code review of this release surfaced 15 findings, all fixed:
  - A local shell that exits on its own now immediately shows the **Shell exited / Restart shell** view (the status changed without notifying the UI), and the **REC indicator clears** when a recorded shell exits or disconnects — previously it stayed red while output was silently dropped after a restart.
  - SFTP panel: **Select All and the selection count respect the active filter** (bulk Delete can no longer touch files hidden by the filter — narrowing the filter also prunes the selection), and a filter with no hits shows **“No matches”** instead of a blank “0 items” pane.
  - Two-panel SFTP: switching a slot's source **remembers the last path per host** and resumes there; returning to the SFTP tab **refreshes listings** that went stale while the screen was kept alive offstage; drag-and-drop no longer disturbs the opposite panel's selection.
  - **Transfers never overwrite silently** — local→local copies refuse a same-named destination file and skip (with a notice) existing files when merging folders, matching the SFTP recursive transfers; a same-host remote relay into the file's own folder is refused instead of truncating and rewriting the file in place.
  - Terminal `Ctrl+C` copy **clears the selection synchronously**, so a rapid second `Ctrl+C` always interrupts even while the clipboard write is still in flight (and a failing clipboard backend can no longer leave the selection stuck); copy/paste/select-all now share **one implementation** across keyboard shortcuts, middle-click and the context menu, with disposal guards after every async gap.
  - The network-stats overlay no longer renders the **previous host's numbers over local terminal tabs**.

### Changed
- Test suite is Windows-portable (temp-dir paths, file-lock handling, unix-socket tests skipped where unsupported).
- Internal refactors: SSH-only consumers (plugins, terminal sharing) read `sshSessions`/`activeSshSession`; `LocalShellService` is injected instead of constructed inline; `TerminalSession` owns its recording folder/title (a future session type can't be misfiled as "local") and the pane renderer fails loudly on unknown session types instead of hard-casting to SSH.

---

## [0.1.23] — 2026-06-04

### Fixed
- **Windows terminal typing (all terminals)** — after the 0.1.22 argv fix, the local PowerShell terminal still ignored printable keys: Enter produced a new prompt line (proving the ConPTY input pipe works) but typed characters never appeared. Root cause is an upstream `xterm.dart` bug ([TerminalStudio/xterm.dart#207](https://github.com/TerminalStudio/xterm.dart/issues/207)): `CustomTextEdit` opens its `TextInputConnection` without a `viewId`, which recent Flutter engines on Windows reject (`Could not set client, view ID is null`) — so text typed through the IME path is dropped while Enter/Tab/paste (hardware-key path) still work. This affected every `TerminalView` on Windows, SSH sessions included. `xterm` is now vendored as a local fork (`packages/xterm`, 4.0.0) that passes `viewId: View.maybeOf(context)?.viewId` to `TextInputConfiguration`, with a regression test asserting the attached text-input client carries the hosting viewId.

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

[Unreleased]: https://github.com/YoursshLabs/yourssh/compare/v0.1.32...HEAD
[0.1.32]: https://github.com/YoursshLabs/yourssh/compare/v0.1.31...v0.1.32
[0.1.31]: https://github.com/YoursshLabs/yourssh/compare/v0.1.30...v0.1.31
[0.1.30]: https://github.com/YoursshLabs/yourssh/compare/v0.1.29...v0.1.30
[0.1.29]: https://github.com/YoursshLabs/yourssh/compare/v0.1.28...v0.1.29
[0.1.28]: https://github.com/YoursshLabs/yourssh/compare/v0.1.27...v0.1.28
[0.1.27]: https://github.com/YoursshLabs/yourssh/compare/v0.1.26...v0.1.27
[0.1.26]: https://github.com/YoursshLabs/yourssh/compare/v0.1.25...v0.1.26
[0.1.25]: https://github.com/YoursshLabs/yourssh/compare/v0.1.24...v0.1.25
[0.1.24]: https://github.com/YoursshLabs/yourssh/compare/v0.1.23...v0.1.24
[0.1.23]: https://github.com/YoursshLabs/yourssh/compare/v0.1.22...v0.1.23
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
