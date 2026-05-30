# YourSSH — Project Plan

## App Info
- **Name:** YourSSH
- **Bundle ID:** com.thangnm.yourssh
- **Target:** macOS + Windows (same Flutter codebase)
- **Stack:** Flutter (UI) + dartssh2 (SSH/SFTP) + Rust core (future optimization)

---

## Architecture

```
┌──────────────────────────────────────────┐
│  Flutter UI (macOS + Windows)            │
│  - xterm widget (terminal)               │
│  - Material 3 / adaptive layout          │
└───────────────┬──────────────────────────┘
                │
┌───────────────▼──────────────────────────┐
│  SSH Service Layer (Dart)                │
│  - dartssh2 (SSH, SFTP, port forward)   │
│  - flutter_secure_storage (credentials) │
└──────────────────────────────────────────┘

  core/ (Rust) — kept for future flutter_rust_bridge
  integration if performance needs arise
```

## Monorepo Structure

```
yourssh/
├── PLAN.md
├── Makefile
├── .gitignore
├── core/                    # Rust core (future optimization)
│   ├── Cargo.toml
│   └── src/
└── app/                     # Flutter app (macOS + Windows)
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   │   ├── host.dart
    │   │   └── ssh_session.dart
    │   ├── services/
    │   │   ├── ssh_service.dart
    │   │   └── storage_service.dart
    │   ├── providers/
    │   │   ├── host_provider.dart
    │   │   └── session_provider.dart
    │   ├── screens/
    │   │   └── main_screen.dart
    │   └── widgets/
    │       ├── host_list.dart
    │       ├── terminal_view.dart
    │       ├── sftp_view.dart
    │       ├── add_host_dialog.dart
    │       └── settings_screen.dart
    ├── macos/
    └── windows/
```

---

## Feature List

### Core Terminal
- [x] Multi-tab terminal
- [ ] Split view
- [ ] Command broadcast
- [ ] Command history + search
- [ ] Auto-reconnect
- [ ] Custom themes (30+ presets)
- [ ] Hotkey customizable

### Connection Management
- [x] Host manager (add/edit/delete/search)
- [ ] SSH key manager
- [x] Jump host / bastion support (v0.1.5+)
- [ ] Port forwarding (Local / Remote / Dynamic)
- [x] Connection profiles

### File Management
- [ ] SFTP file manager (dual-panel)
- [ ] Built-in file editor
- [ ] Drag & drop upload/download
- [ ] Snippet library

### Security
- [x] Secure credential storage (flutter_secure_storage)
- [ ] SSH key auth (Ed25519/RSA)
- [ ] SSH agent forwarding
- [ ] Encrypted vault (export/import)

---

## Sprint Plan

### Sprint 1 — Foundation ✅ (Rust core done)
- [x] Rust core SSH connect (russh) — kept for future
- [x] UniFFI + Swift bindings generated — archived
- **[PIVOT]** Switching to Flutter + dartssh2

### Sprint 2 — Flutter MVP (current)
**Goal: App chạy, connect SSH, terminal hoạt động trên macOS**

- [x] Flutter project created
- [ ] SSH connect (dartssh2, password auth)
- [ ] Terminal view (xterm Flutter widget)
- [ ] Multi-tab sessions
- [ ] Host manager (add/edit/delete)
- [ ] Secure credential storage

**Done when:** Connect SSH, gõ lệnh thấy output trên macOS.

---

### Sprint 3 — Auth + Key Management
- [ ] SSH key auth (Ed25519/RSA)
- [ ] Load keys from ~/.ssh
- [ ] SSH Agent support
- [ ] Key generator UI

---

### Sprint 4 — SFTP File Manager
- [ ] Dual-panel file manager
- [ ] Upload/download
- [ ] Built-in editor
- [ ] Drag & drop

---

### Sprint 5 — Port Forwarding + Tunnels
- [ ] Local/Remote/Dynamic SOCKS5
- [ ] Tunnel manager UI

---

### Sprint 6 — Polish
- [ ] Terminal themes (30+)
- [ ] Auto-reconnect
- [ ] Snippet library
- [ ] Windows testing + polish
- [ ] App icon + branding

---

## Key Dependencies (Flutter)

```yaml
dartssh2: ^2.9.0          # SSH, SFTP, port forwarding
xterm: ^4.0.0             # Terminal emulator widget
flutter_secure_storage: ^9 # Keychain/Credential Manager
provider: ^6.1.0          # State management
shared_preferences: ^2.2  # App settings
```

---

## Build Commands

```bash
# Run on macOS
cd app && flutter run -d macos

# Build macOS app
cd app && flutter build macos

# Build Windows app
cd app && flutter build windows
```
