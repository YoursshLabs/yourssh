# YourSSH — Roadmap

> Direction: **infra workstation for DevOps/SRE managing 10–100+ hosts**, not just an SSH client.
> Current version: 0.1.6 · updated: 2026-05-30 (Command Palette shipped)

This document lists proposed features ordered by priority. Each item can be broken out into its own spec (`docs/superpowers/specs/`) when ready for implementation.

Already shipped (not repeated in roadmap): multi-tab terminal, split view, broadcast, recording (asciicast), snippet, SFTP dual-panel, port forwarding, jump host, Supabase sync + P2P LAN, AI chat sidebar with tool calling, plugin system (DevOps / WebTools / Snippets), Cloudflare tunnel, MCP gateway, mail catcher, code editor (Monaco), customizable hotkeys, TOFU known-hosts, **Command Palette (Cmd/Ctrl+K)** — fuzzy search hosts / nav / snippets / actions.

---

## P0 — Must-have to retain "power" users

| # | Feature | Purpose | Implementation notes |
|---|---|---|---|
| 1 | **Tag + smart group + multi-dimensional filter** | Managing 50+ hosts is unworkable with a flat list. Query syntax like `env:prod role:db region:sg` | Extend `Host` model with `tags: List<String>`, persist in sync; filter chip UI in `hosts_dashboard` |
| 2 | **Import `~/.ssh/config`** | DevOps already have an existing config; manual re-entry loses users | Parser supports `Include`, `ProxyJump`, `Match`, `IdentityFile`. Convert to `Host` + `SshKeyEntry` |
| 3 | **Workspace / session persistence** | Reopening the app restores the correct tabs, layout, and working directory | Persist `SessionProvider` snapshot + `TerminalLayoutProvider` state to prefs |
| 4 | **Search-in-scrollback (Cmd/Ctrl+F)** | A terminal without this is crippled | xterm.dart already exposes the buffer; need a search overlay widget + highlight |
| 5 | **Advanced tab management** | Pin, rename, color tag, drag reorder, duplicate-to-new-tab, tab group | Update `main_screen` tab bar; persist metadata alongside `SshSession` |
| 6 | **Connection health badge** | Latency ping, last-active, auto-reconnect status shown on the tab | Leverage existing `SshService` heartbeat; attach to tab + tooltip |
| 7 | **Internal audit log** | Compliance + retrospective: who/when/host/command | SQLite (drift/sqflite), redact secrets via regex; optional sync |
| 8 | **Bulk action panel** | Select N hosts → connect-all / exec snippet in parallel / SFTP push / diff output | Multi-select UI on host list; backend runs `Future.wait` via `SshService` |
| 9 | **Session template / per-host preset** | Env vars, working dir, shell, theme, startup snippet, recording auto-on | Extend `Host` model; apply when `SessionProvider.start` is called |

## P1 — Differentiation & DevOps depth

### Workflow & integrations
- **Kubernetes panel** — list context/namespace/pod → exec / `logs -f` / 1-click port-forward via `kubectl` (local or remote host).
- **Docker / Compose panel** — container exec, logs, restart on remote host.
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
- Plugin marketplace: real install/uninstall (currently compile-in via `plugin_registry.dart`).
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

1. **Tag/Filter + Import `~/.ssh/config`** — DevOps onboarding: import existing config + organize hosts by env/role.
2. **Workspace persistence + Search-in-scrollback** — two basic terminal features still missing, essential for retaining power users.
3. **Kubernetes panel** — distinct DevOps angle that turns yourssh into an infra workstation rather than a plain SSH client.

---

## How to use this document

- When preparing to implement an item: create a spec `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` using the `superpowers:brainstorming` skill, then plan with `superpowers:writing-plans`.
- When bumping the version or shipping a feature: update the roadmap via the `/yourssh-roadmap` skill (see `~/.claude/skills/yourssh-roadmap/`).
- The roadmap **does not** replace `docs/PLAN.md` (historical sprint log) — this is forward-looking, that is backward-looking.
