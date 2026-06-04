# Architecture

YourSSH is a Flutter desktop app targeting macOS, Windows, and Linux. The active codebase is `app/`; a Rust `core/` library exists for future `flutter_rust_bridge` integration but is not used at runtime.

## Monorepo Layout

```
yourssh/
├── app/                        # Flutter app (the active product)
│   ├── lib/
│   │   ├── main.dart           # Entry point; wires providers and callbacks
│   │   ├── models/             # Data models (Host, SshSession, PortForward, …)
│   │   ├── providers/          # ChangeNotifier state (HostProvider, SessionProvider, …)
│   │   ├── services/           # Business logic (SshService, StorageService, SyncService, …)
│   │   ├── screens/            # Top-level screen (MainScreen)
│   │   ├── widgets/            # All widget files (one per feature area)
│   │   └── theme/              # AppColors, AppTheme constants
│   └── pubspec.yaml
├── packages/
│   ├── dartssh2/               # Local fork of dartssh2 (SSH/SFTP/port-forward)
│   ├── flutter_pty/            # Local fork of flutter_pty (Windows argv[0] fix)
│   ├── xterm/                  # Local fork of xterm (Windows text-input viewId fix)
│   ├── yourssh_plugin_api/     # Abstract plugin interface (YourSSHPlugin)
│   ├── yourssh_devops/         # DevOps Dart plugin (containers, network tools, …)
│   ├── yourssh_web_tools/      # Web Tools Dart plugin
│   ├── yourssh_snippets/       # Snippets Dart plugin
│   └── yourssh_script_engine/  # JS plugin runtime (QuickJS FFI, HookBus, bridges)
└── core/                       # Rust library (inactive at runtime)
```

## Data Flow

```
Flutter UI (widgets/)
  └── Providers (ChangeNotifier, via provider package)
        ├── HostProvider        ─── CRUD hosts → StorageService → SharedPreferences
        ├── SessionProvider     ─── manages SshSession objects
        │     └── SshService    ─── SSHClient/SSHSession maps keyed by hostId
        │           └── dartssh2 (local fork) ──► Remote SSH host
        ├── SyncProvider        ─── SyncService ──► Supabase REST API
        ├── PortForwardProvider ─── persistent tunnel rules
        └── SettingsProvider    ─── app-wide prefs (SharedPreferences)
```

## Key Providers

| Provider | Responsibility |
|---|---|
| `HostProvider` | CRUD for saved hosts; fires `onMutation` → sync push |
| `SessionProvider` | Active `SshSession` objects; auto-reconnect, TOFU, key lookup |
| `KeyProvider` | SSH key entries (path + optional passphrase + cert path) |
| `PortForwardProvider` | Persistent tunnel rules |
| `TunnelProvider` | Runtime tunnel state (separate from rules) |
| `SyncProvider` | Supabase config; `enabled` derived from `isSupabaseConfigured` |
| `SettingsProvider` | App-wide prefs: reconnect, keep-alive, hotkeys, feature flags |
| `AiChatProvider` | AI chat state; multi-provider (Anthropic/OpenAI/Gemini) |
| `RecordingProvider` | Recording library; wired to SessionProvider via callback |

## Key Services

| Service | Responsibility |
|---|---|
| `SshService` | Owns `SSHClient` / `SSHSession` maps; connect, shell, exec, SFTP, disconnect |
| `StorageService` | Secure-first credential storage (Keychain → SharedPreferences fallback) |
| `SyncService` | AES-256-GCM encrypt → Supabase upsert; pull on window focus |
| `P2PSyncService` | One-shot LAN HTTP server + QR key exchange |
| `RecordingService` | Writes `.cast` (Asciinema v2) files per session |
| `HotkeyService` | Global hotkey registration via `hotkey_manager` |

## Credential Storage

```
StorageService.saveSecret(key, value)
  │
  ├── Try: FlutterSecureStorage (Keychain / Credential Manager)
  │     └── On success: purge stale SharedPreferences copy
  └── Fallback: SharedPreferences (plaintext)

Keys: pw_<hostId>  pp_<keyId>  sync_passphrase
```

## Navigation

`MainScreen` (`app/lib/screens/main_screen.dart`) renders:

- Top tab bar — pinned Home/SFTP + scrollable SSH session tabs
- Left sidebar — `NavSection` enum maps to feature screens

## Related Pages

- [Build](Developer-Guide-Build) — how to compile the app
- [Plugin System](Developer-Guide-Plugin-System) — how plugins integrate
