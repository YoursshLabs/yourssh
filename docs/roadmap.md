# YourSSH — Roadmap

> Direction: **infra workstation for DevOps/SRE managing 10–100+ hosts**, not just an SSH client.
> Current version: 0.1.15 · updated: 2026-06-01 (Cloud sync Supabase `sync_data` policy fix)

This document lists proposed features ordered by priority. Each item can be broken out into its own spec (`docs/superpowers/specs/`) when ready for implementation.

Already shipped (not repeated in roadmap): multi-tab terminal, split view, broadcast, recording (asciicast), snippet, SFTP dual-panel, port forwarding, jump host, Supabase sync + P2P LAN, AI chat sidebar with tool calling, plugin system (DevOps / WebTools / Snippets), Cloudflare tunnel, MCP gateway, mail catcher, code editor (Monaco), customizable hotkeys, TOFU known-hosts, **Command Palette (Cmd/Ctrl+K)** — fuzzy search hosts / nav / snippets / actions, **Workspace persistence** — auto-reconnect tabs + layout on relaunch, **Search-in-scrollback (Cmd/Ctrl+F)** — regex, highlights, prev/next navigation, **Script Engine plugin system** — disk-based JS plugins via QuickJS FFI, HookBus (terminal.output / terminal.input / session events), SSH/SFTP/Storage/UI bridges, hot-reload file watcher, PermissionGuard + circuit breaker, consent dialog, manager screen + console log viewer, **Import** — paste SSH config / JSON / CSV with per-host include toggles (`parseSshConfig` in `import_panel.dart`), **Host tagging** — comma-separated tags on the `Host` model, editable in host detail and searchable from the dashboard, **Smart filter + multi-dimensional query (0.1.10)** — `HostQuery` parser with `key:value` faceted AND/OR semantics, toggleable facet chips on hosts dashboard, tag-based search, **Terminal sharing / multiplayer (0.1.13)** — share a live SSH session via Supabase Realtime; guests join with a session code, watch or interact in real time; `ShareSessionService`, `ShareProvider`, `ShareEvent`, split-view watch banner, **Advanced tab management** — rename, color tag, pin, drag reorder; all tab metadata persists per host.

---

## P0 — Must-have to retain "power" users

| # | Feature | Purpose | Implementation notes |
|---|---|---|---|
| 1 | **Bulk action panel** | Select N hosts → connect-all / exec snippet in parallel / SFTP push / diff output | Multi-select UI on host list; backend runs `Future.wait` via `SshService` |
| 2 | **Connection health badge** | Latency ping, last-active, auto-reconnect status shown on the tab | Leverage existing `SshService` heartbeat; attach to tab + tooltip |
| 3 | **Internal audit log** | Compliance + retrospective: who/when/host/command | SQLite (drift/sqflite), redact secrets via regex; optional sync |
| 4 | **Session template / per-host preset** | Env vars, working dir, shell, theme, startup snippet, recording auto-on | Extend `Host` model; apply when `SessionProvider.start` is called |

## P1 — Differentiation & DevOps depth

### Workflow & integrations
- **Kubernetes panel** — _list pods + exec shipped (0.1.12)._ Remaining: context switcher, `logs -f`, 1-click port-forward via `kubectl`.
- **Docker / Compose panel** — _list containers + exec shipped (0.1.12)._ Remaining: logs, restart/stop, Compose awareness.
- **systemd / service browser** — list units, status, `journalctl` tail.
- **Log tail viewer** — multi-file `tail -f` with highlight rules, level filter, pause/resume, save view.
- **SFTP file watcher** — local edit → auto upload (direct competitor to VSCode Remote SSH for fast dev loops).
- **Multi-hop jump chain** — GUI to select bastion → bastion → target.
- **Cloud inventory import** — AWS/GCP/Azure → auto-sync host list by instance tags, refresh on demand.

### Security & identity
- **Secrets vault adapter** — 1Password / Bitwarden / HashiCorp Vault / aws-vault instead of storing passwords in the app.
- **FIDO2 / Yubikey** for SSH (`sk-ssh-ed25519`).
- **Auto key rotation reminder** + age widget per key.
- **Recording redaction** — regex-mask tokens/passwords before writing to `.cast`.

### AI-native (extending AI chat sidebar)
- **Natural language → shell** with diff + confirmation before exec.
- **AI explain output / error** — select text in terminal → "ask AI".
- **AI runbook from recording** — `.cast` → markdown step-by-step.
- **Per-host AI context** — prompt knows the role/env/recent commands for that host.

### Polish existing features
- TOFU dialog: side-by-side diff of old/new fingerprint + "trust temporarily" button.
- Plugin marketplace: hosted catalog for browsing + one-click install of community JS plugins (runtime loading infrastructure already shipped in 0.1.8).
- Sync conflict resolution UI when a pull detects a newer remote version of a locally modified host.
- SFTP: trash instead of direct delete + undo last operation.
- AI chat: explicit tool approval gating + token cost meter.

## P2 — Team / Enterprise (when traction exists)

- Team sync with RBAC + SSO (SAML/OIDC), shared host folder.
- Shared snippet library with approval/review flow.
- Read-only web companion (audit dashboard via existing Cloudflare tunnel).
- Compliance pack: SOC2 audit, key inventory export.
- CLI shim: `yourssh ssh prod-1` sharing the credentials store with the app.
- Plugin marketplace with revenue share (foundation already in `yourssh_plugin_api`).

---

## Top 3 suggestions for the next sprint

1. **Bulk action panel** — select N hosts → connect-all / exec snippet in parallel / SFTP push; the core UX gap after advanced tab management ships.
2. **Connection health badge** — latency + auto-reconnect status on tabs; small surface area, high daily-driver visibility.
3. **Kubernetes panel completion** — context switcher + `logs -f` + 1-click port-forward; the container browser shipped in 0.1.12, finishing the K8s story is the clearest next DevOps milestone.

---

## How to use this document

- When preparing to implement an item: create a spec `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` using the `superpowers:brainstorming` skill, then plan with `superpowers:writing-plans`.
- When bumping the version or shipping a feature: update the roadmap via the `/yourssh-roadmap` skill (see `~/.claude/skills/yourssh-roadmap/`).
- The roadmap **does not** replace `docs/PLAN.md` (historical sprint log) — this is forward-looking, that is backward-looking.
