# YourSSH — Roadmap

> Định hướng: **infra workstation cho DevOps/SRE quản 10–100+ host**, không chỉ là một SSH client.
> Version hiện tại: 0.1.6 · cập nhật: 2026-05-30 (Command Palette shipped)

Tài liệu này liệt kê các feature đề xuất theo độ ưu tiên. Mỗi mục có thể được tách thành một spec (`docs/superpowers/specs/`) riêng khi chuẩn bị thực thi.

Đã có (không lặp lại trong roadmap): multi-tab terminal, split view, broadcast, recording (asciicast), snippet, SFTP dual-panel, port forwarding, jump host, sync Supabase + P2P LAN, AI chat sidebar với tool calling, plugin system (DevOps / WebTools / Snippets), Cloudflare tunnel, MCP gateway, mail catcher, code editor (Monaco), hotkey customizable, TOFU known-hosts, **Command Palette (Cmd/Ctrl+K)** — fuzzy search hosts / nav / snippets / actions.

---

## P0 — Phải có để giữ user "power"

| # | Feature | Mục đích | Ghi chú thực thi |
|---|---|---|---|
| 1 | **Tag + smart group + filter đa chiều** | Quản 50+ host không dùng flat list được. Query kiểu `env:prod role:db region:sg` | Mở rộng `Host` model với `tags: List<String>`, lưu trong sync; UI filter chip ở `hosts_dashboard` |
| 2 | **Import `~/.ssh/config`** | DevOps đã có config sẵn; nhập tay = mất user | Parser hỗ trợ `Include`, `ProxyJump`, `Match`, `IdentityFile`. Convert sang `Host` + `SshKeyEntry` |
| 3 | **Workspace / session persistence** | Mở lại app phục hồi đúng tab, layout, working dir | Persist `SessionProvider` snapshot + `TerminalLayoutProvider` state vào prefs |
| 4 | **Search-in-scrollback (Cmd/Ctrl+F)** | Terminal thiếu cái này coi như què | xterm.dart đã expose buffer; cần overlay search widget + highlight |
| 5 | **Tab management nâng cao** | Pin, rename, color tag, drag reorder, duplicate-to-new-tab, tab group | Sửa `main_screen` tab bar; lưu metadata cùng `SshSession` |
| 6 | **Connection health badge** | Latency ping, last-active, auto-reconnect status hiện trên tab | Tận dụng `SshService` heartbeat đã có; gắn lên tab + tooltip |
| 7 | **Audit log nội bộ** | Compliance + retrospective: who/when/host/command | SQLite (drift/sqflite), redact secrets bằng regex; optional sync |
| 8 | **Bulk action panel** | Chọn N host → connect-all / exec snippet song song / SFTP push / diff output | UI multi-select trên host list; backend chạy `Future.wait` qua `SshService` |
| 9 | **Session template / per-host preset** | Env vars, working dir, shell, theme, startup snippet, recording auto-on | Mở rộng `Host` model; áp dụng khi `SessionProvider.start` |

## P1 — Khác biệt hóa & độ sâu DevOps

### Workflow & integrations
- **Kubernetes panel** — list context/namespace/pod → exec / `logs -f` / port-forward 1-click qua `kubectl` (local hoặc remote host).
- **Docker / Compose panel** — container exec, logs, restart trên remote host.
- **systemd / service browser** — list unit, status, `journalctl` tail.
- **Log tail viewer** — multi-file `tail -f` với highlight rule, level filter, pause/resume, save view.
- **SFTP file watcher** — local edit → auto upload (đối thủ trực tiếp của VSCode Remote SSH cho dev loop nhanh).
- **Multi-hop jump chain** — GUI chọn bastion → bastion → target.
- **Cloud inventory import** — AWS/GCP/Azure → auto sync host list theo tag instance, refresh on demand.

### Security & identity
- **Secrets vault adapter** — 1Password / Bitwarden / HashiCorp Vault / aws-vault thay vì lưu password trong app.
- **FIDO2 / Yubikey** cho SSH (`sk-ssh-ed25519`).
- **Auto key rotation reminder** + age widget per key.
- **Recording redaction** — regex mask token/password trước khi ghi `.cast`.

### AI-native (mở rộng AI chat sidebar)
- **Natural language → shell** với diff + confirm trước exec.
- **AI explain output / error** — chọn text trong terminal → "ask AI".
- **AI runbook từ recording** — `.cast` → markdown step-by-step.
- **Per-host AI context** — prompt biết role/env/recent commands của host này.

### Polish cái đã có
- TOFU dialog: side-by-side diff fingerprint cũ/mới + nút "trust temporarily".
- Plugin marketplace: install/uninstall thực sự (hiện compile-in qua `plugin_registry.dart`).
- Sync conflict resolution UI khi pull thấy remote mới hơn cùng host bị sửa local.
- SFTP: trash thay vì delete thẳng + undo last op.
- AI chat: tool approval gating rõ ràng + token cost meter.

## P2 — Team / Enterprise (khi có traction)

- Team sync với RBAC + SSO (SAML/OIDC), shared host folder.
- Shared snippet library với approval/review flow.
- Web companion read-only (audit dashboard qua Cloudflare tunnel đã có sẵn).
- Compliance pack: SOC2 audit, key inventory export.
- CLI shim: `yourssh ssh prod-1` dùng chung credentials store với app.
- Plugin marketplace có revenue share (đã có nền móng `yourssh_plugin_api`).

---

## Top 3 đề xuất cho sprint kế tiếp

1. **Tag/Filter + Import `~/.ssh/config`** — onboarding DevOps: nhập config sẵn + tổ chức host theo env/role.
2. **Workspace persistence + Search-in-scrollback** — hai tính năng terminal cơ bản còn thiếu, giữ chân user power.
3. **Kubernetes panel** — DevOps angle khác biệt, biến yourssh thành infra workstation thay vì SSH client thuần.

---

## Cách dùng tài liệu này

- Khi chuẩn bị thực thi 1 mục: tạo spec `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` qua skill `superpowers:brainstorming`, rồi plan qua `superpowers:writing-plans`.
- Khi version bump hoặc ship xong feature: cập nhật roadmap qua skill `/yourssh-roadmap` (xem `~/.claude/skills/yourssh-roadmap/`).
- Roadmap **không** thay thế `docs/PLAN.md` (sprint log lịch sử) — đây là forward-looking, kia là backward-looking.
