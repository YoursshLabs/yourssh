# YourSSH

A professional, open-source SSH client for **macOS** and **Windows** built with Flutter. Designed for developers and sysadmins who want a fast, keyboard-friendly terminal experience with built-in SFTP, port forwarding, and secure credential management — all in a clean dark UI.

---

## Features

### Terminal & Connectivity
- **Multi-tab SSH sessions** with named tabs and per-tab connection state
- **Port forwarding** — local, remote, and dynamic SOCKS5 tunnels
- **Local shell** — spawn native macOS/Windows shell alongside SSH sessions
- **xterm-256color** terminal emulation with full PTY support

### File Management
- **Dual-panel SFTP** — browse local and remote filesystems side-by-side
- Upload, download, rename, delete files and directories
- Breadcrumb navigation and file type icons

### Credentials & Security
- **Multiple auth methods**: password, SSH private key
- **OS-level secure storage**: credentials encrypted in macOS Keychain / Windows Credential Manager via `flutter_secure_storage`
- **Known hosts verification**: interactive fingerprint trust dialog on first connect; persistent known-hosts database
- **Zero-knowledge cloud sync**: host configs encrypted client-side (AES) before syncing to Supabase

### Productivity
- **Command snippets** — save and inject reusable command templates
- **Command history** — searchable history per session
- **Hotkeys** — customizable global keyboard shortcuts
- **Host groups** — organize connection profiles into logical folders
- **Broadcast mode** — send the same input to multiple sessions at once
- **Code editor** — edit remote files inline with a built-in plain text editor

### Design
- Dark-only interface with a cohesive green-accent palette
- 6 bundled Powerline-compatible monospace fonts (DejaVu, Inconsolata, Meslo, Source Code Pro, Ubuntu Mono, Roboto Mono)
- Minimum window size enforced (800×600); fully resizable

### DevOps & Developer Tools
- **Network Tools** — ping, cURL, DNS lookup, traceroute, port scan, whois, netstat, disk usage, memory info, HTTP headers, SSL certificate inspection — all run on the active SSH session
- **Cloudflare Tunnel manager** — start/stop quick tunnels via `cloudflared` on the remote host; public URL displayed instantly
- **LAN Share** — serve any local file over HTTP for one-click download on the same network
- **Mail Catcher** — spin up a local SMTP capture server via SSH; inspect emails in a built-in two-panel viewer
- **MCP Server Gateway** — run an MCP server on a remote host and forward it locally for AI tool access
- **S3 Browser** — browse, upload, and delete objects in any S3-compatible bucket (AWS, MinIO, Cloudflare R2, etc.)
- **Vault** — encrypted local credential store for API keys, tokens, and secrets
- **AI Chat Sidebar** — toggle a Claude-powered assistant sidebar for command help and debugging

---

## Screenshots

> _Coming soon — contributions welcome!_

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI Framework | Flutter (Material 3, dark theme) |
| State Management | `provider` (ChangeNotifier) |
| SSH / SFTP / Port Forwarding | `dartssh2` |
| Terminal Emulation | `xterm` |
| Local PTY | `flutter_pty` |
| Secure Storage | `flutter_secure_storage` |
| Cloud Sync Backend | `supabase_flutter` |
| Encryption | `cryptography` (AES) |
| Code Editor | Built-in plain text editor |
| Window Control | `window_manager`, `hotkey_manager` |
| Local Persistence | `shared_preferences`, `file_picker` |

The `core/` directory contains a Rust library skeleton (with `flutter_rust_bridge` scaffolding) kept for potential performance-critical work. It is **not used at runtime** in the current release.

---

## Requirements

| Platform | Minimum Version |
|---|---|
| macOS | 10.14 Mojave |
| Windows | Windows 10 (64-bit) |
| Flutter SDK | 3.12.0+ |
| Dart SDK | 3.12.0+ |

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/<your-org>/yourssh.git
cd yourssh
```

### 2. Install Flutter dependencies

```bash
cd app
flutter pub get
```

### 3. Run in development

```bash
# macOS
flutter run -d macos

# Windows
flutter run -d windows
```

### 4. Build a release binary

```bash
# macOS
flutter build macos

# Windows
flutter build windows
```

### 5. Lint & analyze

```bash
flutter analyze
```

### 6. Run tests

```bash
flutter test
# Single file
flutter test test/widget_test.dart
```

---

## Project Structure

```
yourssh/
├── app/                          # Flutter application (active codebase)
│   ├── lib/
│   │   ├── main.dart             # Entry point — bootstraps all providers
│   │   ├── models/               # Plain data classes (Host, SshSession, etc.)
│   │   ├── providers/            # ChangeNotifier state managers
│   │   ├── services/             # Business logic & external integrations
│   │   ├── screens/              # Top-level screen widgets
│   │   ├── widgets/              # Reusable UI components
│   │   └── theme/                # Dark theme definition (app_theme.dart)
│   ├── assets/
│   │   ├── monaco_editor.html    # Bundled Monaco editor for remote file editing
│   │   └── fonts/powerline/      # 6 Powerline-compatible monospace fonts
│   ├── macos/                    # Xcode project, entitlements, Info.plist
│   ├── windows/                  # Windows build configuration
│   └── pubspec.yaml
│
├── core/                         # Rust core (inactive, reserved for future use)
│   ├── Cargo.toml
│   └── src/
│
├── docs/                         # Design specs and implementation plans
├── scripts/                      # Build and release automation
├── Makefile                      # Rust core build targets
└── CLAUDE.md                     # AI assistant context for this repo
```

---

## Architecture

```
Flutter UI (widgets / screens)
  └── Providers (ChangeNotifier via provider package)
        └── Services (business logic)
              └── dartssh2        — SSH, SFTP, port forwarding
              └── flutter_pty     — local PTY shell
              └── flutter_secure_storage — OS credential vault
              └── shared_preferences    — host list, app settings
              └── supabase_flutter      — optional encrypted sync
```

### Key Providers

| Provider | Responsibility |
|---|---|
| `HostProvider` | CRUD for saved SSH connection profiles, persisted via `StorageService` |
| `SessionProvider` | Lifecycle of active `SshSession` objects; auto-reconnect logic |
| `KeyProvider` | SSH key entries (path + passphrase) |
| `KnownHostsProvider` | Host fingerprint trust database |
| `PortForwardProvider` | Tunnel configuration and active forward tracking |
| `SnippetProvider` | Reusable command snippets |
| `SettingsProvider` | App-wide config (tmux, auto-reconnect, hotkeys, theme) |
| `SyncProvider` | Cloud sync state; delegates to `SyncService` |

### Key Services

| Service | Responsibility |
|---|---|
| `SshService` | Owns `SSHClient` and `SSHSession` maps; connect, exec, shell, SFTP, disconnect |
| `StorageService` | Hosts as JSON in `SharedPreferences`; passwords/passphrases in secure storage |
| `SyncService` | Encrypts host list and pushes/pulls from Supabase |
| `LocalShellService` | Spawns native PTY sessions on macOS/Windows |

---

## Cloud Sync Setup (Optional)

YourSSH can sync your host list across devices using a Supabase project as the backend. All data is **encrypted client-side** before leaving your machine — the server stores only ciphertext.

1. Create a free project at [supabase.com](https://supabase.com).
2. Run the schema migration in `docs/supabase_schema.sql` (if present) or create the required table manually.
3. Add your Supabase URL and anon key in **Settings → Sync** inside the app.
4. Set a strong encryption passphrase — this is the only key that can decrypt your data.

> Sync is fully optional. The app works entirely offline without it.

---

## Contributing

Contributions are welcome. Here's the recommended workflow:

### 1. Fork and branch

```bash
git checkout -b feat/your-feature-name
```

### 2. Follow the existing patterns

- **Models** in `app/lib/models/` — immutable data classes with `copyWith`.
- **Providers** in `app/lib/providers/` — extend `ChangeNotifier`, delegate I/O to services.
- **Services** in `app/lib/services/` — pure logic, no Flutter widget dependencies.
- **Widgets** in `app/lib/widgets/` — stateless where possible; use `Consumer`/`context.watch` to bind to providers.

### 3. Code style

- Run `flutter analyze` — zero warnings expected before submitting.
- Keep comments minimal; prefer self-documenting names.
- Avoid adding dependencies unless essential.

### 4. Test your changes

```bash
flutter test
flutter analyze
```

### 5. Open a pull request

Include a short description of **what** changed and **why**. Screenshots for UI changes are appreciated.

---

## Roadmap

- [ ] Split terminal view (horizontal / vertical panes)
- [ ] Custom terminal color themes (30+ presets)
- [ ] SSH certificate authentication
- [ ] Jump host / bastion proxy support
- [ ] Linux desktop target
- [ ] iOS / iPadOS target (experimental)
- [ ] Rust core integration via `flutter_rust_bridge` for performance-critical paths
- [ ] Plugin / extension system

See [`docs/PLAN.md`](docs/PLAN.md) for the full sprint-by-sprint plan.

---

## License

This project is open-source. License TBD — see [LICENSE](LICENSE) once finalized.

---

## Acknowledgements

- [dartssh2](https://pub.dev/packages/dartssh2) — SSH protocol implementation for Dart
- [xterm.dart](https://pub.dev/packages/xterm) — Terminal emulator widget
- [flutter_pty](https://pub.dev/packages/flutter_pty) — PTY support for local shell
- [Supabase](https://supabase.com) — Open-source Firebase alternative used for sync backend
