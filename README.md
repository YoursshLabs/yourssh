<p align="center">
  <img src="app/assets/app_icon.png" alt="YourSSH" />
  <h1 align="center">YourSSH</h1>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-54C5F8?logo=flutter" alt="Flutter" /></a>
    <a href="https://github.com/thangnm93/yourssh/releases"><img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey?logo=apple" alt="Platform" /></a>
    <a href="https://github.com/thangnm93/yourssh/releases"><img src="https://img.shields.io/github/v/release/thangnm93/yourssh?color=green" alt="Release" /></a>
    <a href="https://github.com/thangnm93/yourssh/actions"><img src="https://img.shields.io/github/actions/workflow/status/thangnm93/yourssh/release.yml?label=build" alt="CI" /></a>
    <a href="https://github.com/thangnm93/yourssh/pulls"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome" /></a>
  </p>
</p>

A professional, open-source SSH client for **macOS**, **Windows**, and **Linux** built with Flutter. Designed for developers and sysadmins who want a fast, keyboard-friendly terminal experience with built-in SFTP, port forwarding, and secure credential management — all in a clean dark UI.

---

## Features

### Terminal & Connectivity
- **Multi-tab SSH sessions** with named tabs and per-tab connection state
- **Split terminal view** — horizontal/vertical pane splitting within a session
- **Port forwarding** — local, remote, and dynamic SOCKS5 tunnels
- **Local shell** — spawn native macOS/Windows/Linux shell alongside SSH sessions
- **xterm-256color** terminal emulation with full PTY support

### File Management
- **Dual-panel SFTP** — browse local and remote filesystems side-by-side
- Upload, download, rename, delete files and directories with transfer progress
- Breadcrumb navigation and file type icons

### Credentials & Security
- **Multiple auth methods**: password, SSH private key
- **OS-level secure storage**: credentials encrypted in macOS Keychain / Windows Credential Manager via `flutter_secure_storage`
- **Known hosts verification**: interactive fingerprint trust dialog on first connect; persistent known-hosts database
- **Zero-knowledge cloud sync**: host configs encrypted client-side (AES) before syncing to Supabase
- **Vault** — encrypted local credential store for API keys, tokens, and secrets (biometric unlock)

### Productivity
- **Command snippets** — save and inject reusable command templates
- **Command history** — searchable history per session
- **Hotkeys** — customizable global keyboard shortcuts
- **Host groups** — organize connection profiles into logical folders
- **Broadcast mode** — send the same input to multiple sessions at once
- **Code editor** — edit remote files inline with a Monaco-powered editor

### Design
- Dark-only interface with a cohesive green-accent palette
- 7 bundled monospace fonts: 6 Powerline-compatible (DejaVu, Inconsolata, Meslo LGS, Source Code Pro, Ubuntu Mono, Roboto Mono) + MesloLGS NF (Nerd Font)
- Minimum window size enforced (800×600); fully resizable

### DevOps & Developer Tools
- **Network Tools** — ping, cURL, DNS lookup, traceroute, port scan, whois, netstat, disk usage, memory info, HTTP headers, SSL certificate inspection — all run on the active SSH session
- **Cloudflare Tunnel manager** — start/stop quick tunnels via `cloudflared` on the remote host; public URL displayed instantly
- **LAN Share** — serve any local file over HTTP for one-click download on the same network
- **Mail Catcher** — spin up a local SMTP capture server via SSH; inspect emails in a built-in two-panel viewer
- **MCP Server Gateway** — run an MCP server on a remote host and forward it locally for AI tool access
- **S3 Browser** — browse, upload, and delete objects in any S3-compatible bucket (AWS, MinIO, Cloudflare R2, etc.)
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
| Encryption | `cryptography` (AES-GCM), `crypto` (AWS Sig V4) |
| Code Editor | Monaco editor via `webview_flutter` |
| Window Control | `window_manager`, `hotkey_manager` |
| Local Persistence | `shared_preferences`, `file_picker` |
| HTTP Server | `shelf` (LAN Share) |
| Network Info | `network_info_plus` |
| Biometric Auth | `local_auth` (Vault) |
| Markdown Rendering | `flutter_markdown` (AI chat) |
| S3 XML Parsing | `xml` |

---

## Requirements

| Platform | Minimum Version |
|---|---|
| macOS | 10.14 Mojave |
| Windows | Windows 10 (64-bit) |
| Linux | Ubuntu 20.04+ / any GTK3-compatible distro |
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

# Linux
flutter run -d linux
```

### 4. Build a release binary

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
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
│   │   ├── models/               # Plain data classes
│   │   ├── providers/            # ChangeNotifier state managers
│   │   ├── services/             # Business logic & external integrations
│   │   ├── screens/              # Top-level screen (main_screen.dart)
│   │   ├── widgets/              # UI components
│   │   │   └── web_tools/        # Embedded browser, HTTP client, utility tools
│   │   └── theme/                # Dark theme definition (app_theme.dart)
│   ├── assets/
│   │   ├── monaco_editor.html    # Bundled Monaco editor for remote file editing
│   │   ├── app_icon.png
│   │   └── fonts/
│   │       ├── powerline/        # 6 Powerline-compatible monospace fonts
│   │       └── nerd/             # MesloLGS NF (Nerd Font, 4 variants)
│   ├── macos/                    # Flutter macOS runner (Xcode entitlements, Info.plist)
│   ├── windows/                  # Flutter Windows build configuration
│   ├── linux/                    # Flutter Linux build configuration (CMake)
│   └── pubspec.yaml
│
├── macos/                        # Xcode project files (xcodegen — project.yml)
├── supabase/migrations/          # Database schema migrations
├── scripts/                      # Build and release automation
├── Makefile                      # Xcode project generation targets
└── CLAUDE.md                     # AI assistant context for this repo
```

---

## Architecture

```
Flutter UI (widgets / screens)
  └── Providers (ChangeNotifier via provider package)
        └── Services (business logic)
              └── dartssh2              — SSH, SFTP, port forwarding
              └── flutter_pty           — local PTY shell
              └── flutter_secure_storage — OS credential vault
              └── shared_preferences    — host list, app settings
              └── supabase_flutter      — optional encrypted sync
              └── shelf                 — local HTTP server (LAN Share)
```

### Key Providers

| Provider | Responsibility |
|---|---|
| `HostProvider` | CRUD for saved SSH connection profiles, persisted via `StorageService` |
| `SessionProvider` | Lifecycle of active `SshSession` objects; auto-reconnect logic |
| `LocalSessionProvider` | Lifecycle of local PTY shell sessions |
| `KeyProvider` | SSH key entries (path + passphrase) |
| `KnownHostsProvider` | Host fingerprint trust database |
| `PortForwardProvider` | Tunnel configuration and active forward tracking |
| `TunnelProvider` | Cloudflare and MCP gateway tunnel state |
| `SnippetProvider` | Reusable command snippets |
| `CommandHistoryProvider` | Per-session command history |
| `SettingsProvider` | App-wide config (tmux, auto-reconnect, hotkeys, theme) |
| `SyncProvider` | Cloud sync state; delegates to `SyncService` |
| `SftpPanelProvider` | SFTP panel state (current path, selection, loading) |
| `SftpTransferProvider` | Active transfer queue and progress tracking |
| `LocalFilePanelProvider` | Local filesystem panel state for dual-panel SFTP |
| `TerminalLayoutProvider` | Split-terminal layout (horizontal/vertical panes) |
| `AiChatProvider` | AI chat sidebar state and message history |

### Key Services

| Service | Responsibility |
|---|---|
| `SshService` | Owns `SSHClient` and `SSHSession` maps; connect, exec, shell, SFTP, disconnect |
| `StorageService` | Hosts as JSON in `SharedPreferences`; passwords/passphrases in secure storage |
| `SyncService` | Encrypts host list and pushes/pulls from Supabase |
| `SyncEncryption` | AES-GCM encrypt/decrypt for sync data |
| `SupabaseService` | Supabase client wrapper (auth, RPC calls) |
| `LocalShellService` | Spawns native PTY sessions on macOS/Windows/Linux |
| `PtyRunner` | Low-level PTY wrapper used by `LocalShellService` |
| `SftpFileOpsService` | SFTP file operations (copy, move, rename, delete) |
| `SftpTransferService` | Chunked SFTP upload/download with progress callbacks |
| `CloudflareTunnelService` | Start/stop `cloudflared` quick tunnels on the remote host |
| `LanShareService` | HTTP file server on LAN via `shelf` |
| `MailCatcherService` | Local SMTP capture server via SSH port forward |
| `McpGatewayService` | Forward MCP server from remote host to local port |
| `S3Service` | S3-compatible bucket operations with AWS Signature V4 |
| `NetworkStatsService` | Real-time network traffic stats for the overlay widget |
| `WebToolsService` | Runs network diagnostic commands on the active SSH session |
| `HotkeyService` | Register and dispatch global keyboard shortcuts |

---

## Cloud Sync Setup (Optional)

YourSSH can sync your host list across devices using a Supabase project as the backend. All data is **encrypted client-side** before leaving your machine — the server stores only ciphertext.

1. Create a free project at [supabase.com](https://supabase.com).
2. Run the migrations in `supabase/migrations/` against your project.
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

- [ ] Custom terminal color themes (30+ presets)
- [ ] SSH certificate authentication
- [ ] Jump host / bastion proxy support
- [x] Linux desktop target
- [ ] iOS / iPadOS target (experimental)
- [ ] Plugin / extension system

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgements

- [dartssh2](https://pub.dev/packages/dartssh2) — SSH protocol implementation for Dart
- [xterm.dart](https://pub.dev/packages/xterm) — Terminal emulator widget
- [flutter_pty](https://pub.dev/packages/flutter_pty) — PTY support for local shell
- [Supabase](https://supabase.com) — Open-source Firebase alternative used for sync backend
