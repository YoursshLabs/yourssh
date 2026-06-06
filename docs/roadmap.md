# YourSSH — Roadmap

> Direction: **infra workstation for DevOps/SRE managing 10–100+ hosts**, not just an SSH client.
> Current version: 0.1.30 · updated: 2026-06-06 (release 0.1.30: bulk action panel, dashboard grid/list view + sorting, agent forwarding observability, connection chain editor, jump-host fix on auto-connect paths)

This document lists proposed features ordered by priority. Each item can be broken out into its own spec (`docs/superpowers/specs/`) when ready for implementation.

Already shipped (not repeated in roadmap): multi-tab terminal, split view, broadcast, recording (asciicast), snippet, SFTP dual-panel, port forwarding, jump host, Supabase sync + P2P LAN, AI chat sidebar with tool calling, plugin system (DevOps / WebTools / Snippets), Cloudflare tunnel, MCP gateway, mail catcher, code editor (Monaco), customizable hotkeys, TOFU known-hosts, **Command Palette (Cmd/Ctrl+K)** — fuzzy search hosts / nav / snippets / actions, **Workspace persistence** — auto-reconnect tabs + layout on relaunch, **Search-in-scrollback (Cmd/Ctrl+F)** — regex, highlights, prev/next navigation, **Script Engine plugin system** — disk-based JS plugins via QuickJS FFI, HookBus (terminal.output / terminal.input / session events), SSH/SFTP/Storage/UI bridges, hot-reload file watcher, PermissionGuard + circuit breaker, consent dialog, manager screen + console log viewer, **Import** — paste SSH config / JSON / CSV with per-host include toggles (`parseSshConfig` in `import_panel.dart`), **Host tagging** — comma-separated tags on the `Host` model, editable in host detail and searchable from the dashboard, **Smart filter + multi-dimensional query (0.1.10)** — `HostQuery` parser with `key:value` faceted AND/OR semantics, toggleable facet chips on hosts dashboard, tag-based search, **Terminal sharing / multiplayer (0.1.13)** — share a live SSH session via Supabase Realtime; guests join with a session code, watch or interact in real time; `ShareSessionService`, `ShareProvider`, `ShareEvent`, split-view watch banner, **Advanced tab management** — rename, color tag, pin, drag reorder; all tab metadata persists per host, **Connection health badge (0.1.17)** — live latency-driven dot per session tab (green/amber/red/grey + pulse), hover tooltip with uptime / last-ping / reconnect count; `HealthMonitorService` pings the live channel (`SSHClient.ping`) as sole pinger, 5s timeout surfaces half-open silent drops, **Shell integration (0.1.18)** — injected bash/zsh prompt-hooks emit OSC 7 + OSC 133 captured via xterm `onPrivateOSC`; cwd on the session tab, per-command status gutter (green/red/grey), jump-to-prompt (`Cmd/Ctrl+↑/↓`), and cwd-aware path autocomplete in the input bar; auto-on with per-host + global opt-out, **In-app updates (0.1.19)** — checks GitHub `releases/latest` on launch (24h debounce) + manual check in Settings; since 0.1.29 also re-checks while the app stays running (6h periodic timer + window-focus check, same 24h debounce) so the notification bell picks up new releases without a restart; dismissible update banner + Settings Updates section; downloads the correct OS/arch artifact and hands off to the OS installer (assisted flow, unsigned-app friendly: macOS strips quarantine + opens the DMG, Windows runs the installer, Linux opens the package); falls back to the Releases page when no artifact matches (e.g. Intel Mac); `UpdateService` + `UpdateProvider` + `UpdateBanner`, **Sudo SFTP (0.1.20)** — per-host SFTP mode running the entire SFTP session as root through `sudo` over an exec channel (WinSCP-style); distro auto-detection, `NOPASSWD` guidance, root badge on elevated panels, **External edit + Open with… (0.1.20–0.1.21)** — open remote files with the OS default app or any installed app (hover submenu; per-OS discovery via `NSWorkspace` / XDG `.desktop` / Windows registry); the local copy is watched and auto-uploaded on every save; plain-text editor fallback where Monaco is unavailable, **SFTP View mode (0.1.21)** — read-only preview separate from Edit, **Invisible shell-integration injection (0.1.21)** — bracketed-paste readiness detection + `read -rs` two-phase handshake delivers the OSC hook installer without ever echoing into the terminal or recordings, **Terminal snippets panel (0.1.21)** — collapsible right-side panel in the terminal workspace to browse/search/copy/run snippets against the active pane, backed by the new plugin `sendInput` API, **Unified terminal tabs (0.1.24)** — local shell sessions are first-class tabs in the global top bar (`TerminalSession` model), split into panes alongside SSH, recordable to asciicast, **SFTP two-panel with switchable sources (0.1.24)** — per-panel Local/host source chip, unified headers (filter + actions), clickable breadcrumbs (#41), workspace kept alive across tab switches (#42), **Terminal copy/paste UX (0.1.24)** — selection-gated Ctrl+C copy (SIGINT preserved), Ctrl(+Shift)+V paste, right-click Copy/Paste/Select All menu, middle-click paste (#43), readable semi-transparent selection colors in all themes (#40), **Notification bell (0.1.25)** — bell in the top tab bar with unread badge + anchored popover; update-available items carry a one-click Update button, unexpected session drops (no pending auto-reconnect) are collected per session; mark-read on open, per-item dismiss, clear all; in-memory `NotificationCenterProvider` (deduped, capped at 50), **Terminal appearance side panel** — tune icon in the terminal toolbar opens a right-side panel (mutually exclusive with the snippets panel via the `SidePanel` enum; shared `WorkspaceSidePanel` frame) to change color theme, font size (live preview while dragging, persisted once on release), and font family without leaving the workspace; controls shared with Settings → Terminal via `TerminalAppearanceControls`, **Terminal theme catalog 35 → 44** — added Kanagawa Dragon/Lotus, Tokyo Night Day, Nord Light, Light Owl, Flexoki Dark/Light, Aura, and Cyberpunk from their authors' published palettes, grouped next to their families in the picker, with visibility-tuned cursor/selection/search colors on the light variants, **Port forwarding runtime (0.1.27)** — saved local/remote/dynamic SOCKS5 rules actually start and stop (`PortForwardService` over the dartssh2 forward APIs behind a testable `TunnelTransport` abstraction); tunnels reuse the host's open SSH client or auto-connect with stored credentials (no terminal tab required), auto-reconnect with 2 s → 30 s exponential backoff keeping local listeners bound across drops, per-rule edit panel, auto-start on launch, live connection counters, inline error reporting, **SSH Agent Forwarding (0.1.28, #49)** — per-host toggle (like `ssh -A`); forwarded `auth-agent@openssh.com` channels are served by the local system agent (`SSH_AUTH_SOCK` / Windows OpenSSH agent pipe) with fallback to app-Keychain keys when no system agent is running; requested on shell channels only, server refusal shows a terminal warning instead of killing the session (`AgentForwardingHandler`, `SystemAgentProxy.roundtrip`, dartssh2 fork agent-channel support), **Strict KEX (0.1.29)** — CVE-2023-48795 "Terrapin" mitigation in the dartssh2 fork: sequence numbers reset after every NEWKEYS, non-KEX messages during the initial exchange terminate the connection, KEXINIT must be the first packet, **Quick wins (0.1.29)** — middle-click closes unpinned session tabs; right-click context menu on port-forward rules with Duplicate (new id, "(copy)" label, auto-start off); distro-level OS icons (`/etc/os-release` ID → ubuntu/debian/fedora/centos/rocky/alma/alpine/amazon/arch/suse/redhat glyphs) on the hosts dashboard and SSH session tabs (`os_detection.dart`, `SessionTab` extracted from main_screen); empty-password SSH behavior locked in by tests (blank passwords are never persisted; connect sends ''), **SFTP permissions editor + unified entry context menu (0.1.29)** — chmod dialog (9-checkbox rwx grid two-way synced with a validated octal field: octal-only input, 3–4 digits, Apply gated while invalid; unknown current permissions fall back to stat() then warn and gate Apply instead of offering 000) on both the remote SFTP and local panels; `SftpFileOpsService.chmod` with a hardened recursive walk (entries with omitted modes classified via lstat, symlinks never followed — SETSTAT would chmod the target, directory modes applied post-order so a restrictive mode can't lock the walk out, file chmods batched 8-wide) sharing its `listWalkChildren` classification with recursive delete; st_mode carried on `SftpEntry`/`LocalEntry` from listing/scan time (no blocking stat at dialog-open); one shared `EntryContextMenu` for both panels (Open / Open with / View / Edit / Copy to target with up-front feasibility reasons incl. the same-folder block / Refresh / New folder / Permissions / Rename / Delete) wired through the dual-panel transfer matrix; shared app-launch helpers extracted to `util/app_launcher.dart`, **Bulk action panel (0.1.30)** — SELECT mode on the hosts dashboard (per-card checkboxes, filter-aware Select all, Esc to exit) with Connect all (skips already-connected hosts, confirms before opening more than 5 tabs), Run command in parallel (free text or snippet; bounded concurrency, 30 s per-host timeout, per-host failure isolation; per-host exit code / duration / expandable stdout+stderr; a Diff tab groups identical outputs against a promotable baseline and side-by-side compares any two hosts), and Push files to one remote path on every host (destination created if missing, per-host byte progress, cancel); closing a dialog mid-run confirms, cancels queued hosts and lets in-flight operations record their real result, **Dashboard grid & list view + sorting (0.1.30)** — card grid ↔ compact one-line list toggle and a sort dropdown (name / creation date / hostname, asc/desc), both persisted across restarts; default order Name A–Z, **Agent forwarding observability (0.1.30)** — pre-connect agent status line in the host panel (system agent identities / app-Keychain fallback / nothing to serve), live per-session key icon on the session tab (grey ready / green active / orange Keychain fallback / red refused), and a notification-bell item with tap-to-jump when the server refuses forwarding, **Connection Chain editor (0.1.30)** — Termius-style visual chain replacing the jump-host dropdown in the host panel (bastion card → arrow → destination, searchable Add-a-Host picker, agent-forwarding key icon, Clear; `HostChainEditor`, single hop), **Jump host on auto-connect paths (0.1.30)** — `ensureClient` (SFTP / exec / port forwarding) now resolves `Host.jumpHostId` via `defaultJumpHostLookup`, so hosts behind a bastion tunnel correctly outside interactive sessions; plus `tool/jump_probe.dart`, a layer-by-layer jump diagnostic CLI.

---

## P0 — Must-have to retain "power" users

| # | Feature | Purpose | Implementation notes |
|---|---|---|---|
| 1 | **Internal audit log** | Compliance + retrospective: who/when/host/command | SQLite (drift/sqflite), redact secrets via regex; optional sync |
| 2 | **Session template / per-host preset** | Env vars, working dir, shell, theme, startup snippet, recording auto-on | Extend `Host` model; apply when `SessionProvider.start` is called |

## P1 — Differentiation & DevOps depth

### Workflow & integrations
- **Kubernetes panel** — _list pods + exec shipped (0.1.12)._ Remaining: context switcher, `logs -f`, 1-click port-forward via `kubectl`.
- **Docker / Compose panel** — _list containers + exec shipped (0.1.12)._ Remaining: logs, restart/stop, Compose awareness.
- **systemd / service browser** — list units, status, `journalctl` tail.
- **Log tail viewer** — multi-file `tail -f` with highlight rules, level filter, pause/resume, save view.
- **Multi-hop jump chain** — _visual chain editor shipped single-hop (0.1.30)._ Remaining: multiple hops (bastion → bastion → target) — `Host.jumpHostId` becomes a list, `SshService` dials recursively, chain UI re-enables Add a Host with a hop already set.
- **Cloud inventory import** — AWS/GCP/Azure → auto-sync host list by instance tags, refresh on demand.
- **Parameterized workflows / runbooks** — snippets with typed parameters prompted on run; snippet **packages** (group related snippets, import/export as a bundle); on-demand reuse + foundation for team-shareable workflows. Extends `yourssh_snippets`.

### Terminal UX & protocol support
- **Richer autocomplete** — _cwd-aware path completion shipped (0.1.18)._ Remaining: option / argument-aware completion sourced from snippets + built-ins, and suggesting a matching key/identity on password prompts.
- **Keyword highlighting** — user-defined regex rules (defaults: Error/Warning/Fail) tint matching terminal output; wire through the existing HookBus `terminal.output` hook or the xterm fork.
- **OSC 52 clipboard** — let remote apps (tmux, vim) write to the local clipboard through the escape sequence; xterm fork addition, opt-in per host for safety.
- **Grid split layouts** — beyond the current 2-pane horizontal/vertical: 2×2+, drag-to-rearrange panes, per-pane resize persistence. Extends `TerminalLayoutProvider`.
- **Terminal emulation & charset per host** — selectable `TERM` type (xterm-256color / linux / vt100) and charset (UTF-8 / legacy codepages) for network gear and legacy servers.
- **Zmodem (rz/sz) inline transfer** — direct file transfer inside an active SSH shell without switching to the SFTP panel.
- **In-app RDP client (issue #44)** — control Windows / xrdp desktops inside the app (screen + mouse/keyboard + clipboard, NLA, direct or SSH-tunneled). **Spec + implementation plan ready, implementation deferred:** `docs/superpowers/specs/2026-06-04-in-app-rdp-client-design.md` + `docs/superpowers/plans/2026-06-04-in-app-rdp-client.md` (IronRDP via flutter_rust_bridge, 20 tasks, adversarially reviewed).
- **Telnet + serial console** — multi-protocol terminal beyond SSH for legacy/network gear. Larger lift: the dartssh2 fork is SSH-only.

### Security & identity
- **Secrets vault adapter** — 1Password / Bitwarden / HashiCorp Vault / aws-vault instead of storing passwords in the app.
- **FIDO2 / Yubikey** for SSH (`sk-ssh-ed25519`).
- **In-app SSH key generation** — generate ED25519 / ECDSA / RSA pairs from the Keychain screen, export/copy the public key (ssh-copy-id-style deploy to a host as stretch); today `KeyProvider` only references existing files.
- **Biometric-protected keys** — private keys gated behind Touch ID / Windows Hello (Secure Enclave / TPM-backed where available) instead of a stored passphrase.
- **TOTP autofill for keyboard-interactive** — store a per-host TOTP secret in secure storage and auto-answer 2FA prompts during auth.
- **Post-quantum crypto** — `mlkem768x25519-sha256` KEX and ML-DSA keys in the dartssh2 fork, tracking OpenSSH 9.x+ defaults.
- **Connection proxy support** — HTTP CONNECT / SOCKS5 proxy option per host for restricted networks (complements the existing jump-host chain).
- **Auto key rotation reminder** + age widget per key.
- **Recording redaction** — regex-mask tokens/passwords before writing to `.cast`.

### AI-native (extending AI chat sidebar)
- **Inline NL → shell** — trigger from the terminal input itself (not just the sidebar) with diff + confirmation before exec; today the AI is sidebar-only.
- **AI explain output / error** — select text in terminal → "ask AI"; right-click an error to explain it.
- **AI-assisted snippet/workflow authoring** — auto-generate name, description, and parameters for a captured command.
- **AI runbook from recording** — `.cast` → markdown step-by-step.
- **Per-host AI context** — prompt knows the role/env/recent commands for that host.

### Polish existing features
- TOFU dialog: side-by-side diff of old/new fingerprint + "trust temporarily" button.
- Plugin marketplace: hosted catalog for browsing + one-click install of community JS plugins (runtime loading infrastructure already shipped in 0.1.8).
- Sync conflict resolution UI when a pull detects a newer remote version of a locally modified host.
- SFTP: trash instead of direct delete + undo last operation.
- AI chat: explicit tool approval gating + token cost meter.
- Recording library: full-text search inside `.cast` content (find the session where a command was run).
- Import panel: PuTTY session import (registry on Windows, `.ppk` key conversion) on top of the shipped SSH config/JSON/CSV.
- Named workspace profiles: save/switch multiple tab+layout sets (extends the shipped workspace persistence).

> **Candidate gaps (needs follow-up research before promoting):** bundled X-server, terminal scripting/automation (e.g. Python), output triggers + tmux integration, and in-app VNC (RDP promoted to P1 with a ready plan — see above). Unverified this pass.

## P2 — Team / Enterprise (when traction exists)

- Team sync with RBAC + SSO (SAML/OIDC) + shared "vault" — share not just hosts but SSH keys, port-forward rules, known hosts, and snippet packages, with granular per-vault access control.
- Shared snippet library with approval/review flow.
- Read-only web companion (audit dashboard via existing Cloudflare tunnel).
- Compliance pack: SOC2 audit, key inventory export.
- CLI shim: `yourssh ssh prod-1` sharing the credentials store with the app.
- Plugin marketplace with revenue share (foundation already in `yourssh_plugin_api`).

---

## Top 3 suggestions for the next sprint

1. **Session template / per-host preset** — env vars, working dir, startup snippet, auto-record per host; pairs naturally with the health badge now that per-session metadata is richer.
2. **Kubernetes panel completion** — context switcher + `logs -f` + 1-click port-forward; the container browser shipped in 0.1.12, finishing the K8s story is the clearest next DevOps milestone.
3. **Internal audit log** — who/when/host/command with secret redaction; the natural follow-up now that bulk run can touch N hosts in one action.

---

## How to use this document

- When preparing to implement an item: create a spec `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` using the `superpowers:brainstorming` skill, then plan with `superpowers:writing-plans`.
- When bumping the version or shipping a feature: update the roadmap via the `/yourssh-roadmap` skill (see `~/.claude/skills/yourssh-roadmap/`).
- The roadmap **does not** replace `docs/PLAN.md` (historical sprint log) — this is forward-looking, that is backward-looking.
