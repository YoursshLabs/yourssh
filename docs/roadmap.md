# YourSSH — Roadmap

> Direction: **infra workstation for DevOps/SRE managing 10–100+ hosts**, not just an SSH client.
> Current version: 0.1.22 · updated: 2026-06-04 (Windows local terminal input fix — vendored flutter_pty fork · SFTP download robustness · Windows Open-with discovery fixes)

This document lists proposed features ordered by priority. Each item can be broken out into its own spec (`docs/superpowers/specs/`) when ready for implementation.

Already shipped (not repeated in roadmap): multi-tab terminal, split view, broadcast, recording (asciicast), snippet, SFTP dual-panel, port forwarding, jump host, Supabase sync + P2P LAN, AI chat sidebar with tool calling, plugin system (DevOps / WebTools / Snippets), Cloudflare tunnel, MCP gateway, mail catcher, code editor (Monaco), customizable hotkeys, TOFU known-hosts, **Command Palette (Cmd/Ctrl+K)** — fuzzy search hosts / nav / snippets / actions, **Workspace persistence** — auto-reconnect tabs + layout on relaunch, **Search-in-scrollback (Cmd/Ctrl+F)** — regex, highlights, prev/next navigation, **Script Engine plugin system** — disk-based JS plugins via QuickJS FFI, HookBus (terminal.output / terminal.input / session events), SSH/SFTP/Storage/UI bridges, hot-reload file watcher, PermissionGuard + circuit breaker, consent dialog, manager screen + console log viewer, **Import** — paste SSH config / JSON / CSV with per-host include toggles (`parseSshConfig` in `import_panel.dart`), **Host tagging** — comma-separated tags on the `Host` model, editable in host detail and searchable from the dashboard, **Smart filter + multi-dimensional query (0.1.10)** — `HostQuery` parser with `key:value` faceted AND/OR semantics, toggleable facet chips on hosts dashboard, tag-based search, **Terminal sharing / multiplayer (0.1.13)** — share a live SSH session via Supabase Realtime; guests join with a session code, watch or interact in real time; `ShareSessionService`, `ShareProvider`, `ShareEvent`, split-view watch banner, **Advanced tab management** — rename, color tag, pin, drag reorder; all tab metadata persists per host, **Connection health badge (0.1.17)** — live latency-driven dot per session tab (green/amber/red/grey + pulse), hover tooltip with uptime / last-ping / reconnect count; `HealthMonitorService` pings the live channel (`SSHClient.ping`) as sole pinger, 5s timeout surfaces half-open silent drops, **Shell integration (0.1.18)** — injected bash/zsh prompt-hooks emit OSC 7 + OSC 133 captured via xterm `onPrivateOSC`; cwd on the session tab, per-command status gutter (green/red/grey), jump-to-prompt (`Cmd/Ctrl+↑/↓`), and cwd-aware path autocomplete in the input bar; auto-on with per-host + global opt-out, **In-app updates (0.1.19)** — checks GitHub `releases/latest` on launch (24h debounce) + manual check in Settings; dismissible update banner + Settings Updates section; downloads the correct OS/arch artifact and hands off to the OS installer (assisted flow, unsigned-app friendly: macOS strips quarantine + opens the DMG, Windows runs the installer, Linux opens the package); falls back to the Releases page when no artifact matches (e.g. Intel Mac); `UpdateService` + `UpdateProvider` + `UpdateBanner`, **Sudo SFTP (0.1.20)** — per-host SFTP mode running the entire SFTP session as root through `sudo` over an exec channel (WinSCP-style); distro auto-detection, `NOPASSWD` guidance, root badge on elevated panels, **External edit + Open with… (0.1.20–0.1.21)** — open remote files with the OS default app or any installed app (hover submenu; per-OS discovery via `NSWorkspace` / XDG `.desktop` / Windows registry); the local copy is watched and auto-uploaded on every save; plain-text editor fallback where Monaco is unavailable, **SFTP View mode (0.1.21)** — read-only preview separate from Edit, **Invisible shell-integration injection (0.1.21)** — bracketed-paste readiness detection + `read -rs` two-phase handshake delivers the OSC hook installer without ever echoing into the terminal or recordings, **Terminal snippets panel (0.1.21)** — collapsible right-side panel in the terminal workspace to browse/search/copy/run snippets against the active pane, backed by the new plugin `sendInput` API.

---

## P0 — Must-have to retain "power" users

| # | Feature | Purpose | Implementation notes |
|---|---|---|---|
| 1 | **Bulk action panel** | Select N hosts → connect-all / exec snippet in parallel / SFTP push / diff output | Multi-select UI on host list; backend runs `Future.wait` via `SshService` |
| 2 | **Internal audit log** | Compliance + retrospective: who/when/host/command | SQLite (drift/sqflite), redact secrets via regex; optional sync |
| 3 | **Session template / per-host preset** | Env vars, working dir, shell, theme, startup snippet, recording auto-on | Extend `Host` model; apply when `SessionProvider.start` is called |

## P1 — Differentiation & DevOps depth

### Workflow & integrations
- **Kubernetes panel** — _list pods + exec shipped (0.1.12)._ Remaining: context switcher, `logs -f`, 1-click port-forward via `kubectl`.
- **Docker / Compose panel** — _list containers + exec shipped (0.1.12)._ Remaining: logs, restart/stop, Compose awareness.
- **systemd / service browser** — list units, status, `journalctl` tail.
- **Log tail viewer** — multi-file `tail -f` with highlight rules, level filter, pause/resume, save view.
- **Multi-hop jump chain** — GUI to select bastion → bastion → target.
- **Cloud inventory import** — AWS/GCP/Azure → auto-sync host list by instance tags, refresh on demand.
- **Parameterized workflows / runbooks** — snippets with typed parameters prompted on run; on-demand reuse + foundation for team-shareable workflows. Extends `yourssh_snippets`.

### Terminal UX & protocol support
- **Richer autocomplete** — _cwd-aware path completion shipped (0.1.18)._ Remaining: option / argument-aware completion sourced from snippets + built-ins, and suggesting a matching key/identity on password prompts.
- **Zmodem (rz/sz) inline transfer** — direct file transfer inside an active SSH shell without switching to the SFTP panel.
- **Telnet + serial console** — multi-protocol terminal beyond SSH for legacy/network gear. Larger lift: the dartssh2 fork is SSH-only.

### Security & identity
- **Secrets vault adapter** — 1Password / Bitwarden / HashiCorp Vault / aws-vault instead of storing passwords in the app.
- **FIDO2 / Yubikey** for SSH (`sk-ssh-ed25519`).
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

> **Candidate gaps (needs follow-up research before promoting):** bundled X-server, terminal scripting/automation (e.g. Python), output triggers + tmux integration, and multi-protocol consolidation (RDP/VNC). Unverified this pass.

## P2 — Team / Enterprise (when traction exists)

- Team sync with RBAC + SSO (SAML/OIDC) + shared "vault" — share not just hosts but SSH keys, port-forward rules, known hosts, and snippet packages, with granular per-vault access control.
- Shared snippet library with approval/review flow.
- Read-only web companion (audit dashboard via existing Cloudflare tunnel).
- Compliance pack: SOC2 audit, key inventory export.
- CLI shim: `yourssh ssh prod-1` sharing the credentials store with the app.
- Plugin marketplace with revenue share (foundation already in `yourssh_plugin_api`).

---

## Top 3 suggestions for the next sprint

1. **Bulk action panel** — select N hosts → connect-all / exec snippet in parallel / SFTP push; the core UX gap after advanced tab management ships.
2. **Kubernetes panel completion** — context switcher + `logs -f` + 1-click port-forward; the container browser shipped in 0.1.12, finishing the K8s story is the clearest next DevOps milestone.
3. **Session template / per-host preset** — env vars, working dir, startup snippet, auto-record per host; pairs naturally with the health badge now that per-session metadata is richer.

---

## How to use this document

- When preparing to implement an item: create a spec `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` using the `superpowers:brainstorming` skill, then plan with `superpowers:writing-plans`.
- When bumping the version or shipping a feature: update the roadmap via the `/yourssh-roadmap` skill (see `~/.claude/skills/yourssh-roadmap/`).
- The roadmap **does not** replace `docs/PLAN.md` (historical sprint log) — this is forward-looking, that is backward-looking.
