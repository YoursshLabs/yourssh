# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Run on macOS (primary target)
cd app && flutter run -d macos

# Run on Windows
cd app && flutter run -d windows

# Build
cd app && flutter build macos
cd app && flutter build windows

# Lint / analyze
cd app && flutter analyze

# Tests
cd app && flutter test
cd app && flutter test test/widget_test.dart   # single test file
```

## Makefile targets (Rust core — inactive/future)

```bash
make setup          # Install deps (Rust targets, xcodegen)
make core           # Build universal .a + Swift bindings
make swift-bindings # Regenerate Swift bindings only
make open           # Generate Xcode project and open it
make clean          # Remove Rust build artifacts + generated bindings
```

## Architecture

The active codebase is `app/` — a Flutter app targeting macOS and Windows. The `core/` Rust library is **not currently used at runtime**; it was built in Sprint 1 and kept for future `flutter_rust_bridge` integration if performance requires it.

**Data flow:**

```
Flutter UI (widgets/screens)
  └── Providers (ChangeNotifier, via provider package)
        └── SshService / StorageService
              └── dartssh2 (SSH, SFTP, port forwarding)
              └── flutter_secure_storage (Keychain / Credential Manager)
              └── shared_preferences (host list, app settings)
```

**Providers** (`app/lib/providers/`):
- `HostProvider` — CRUD for saved SSH hosts, persisted via `StorageService`
- `SessionProvider` — manages active `SshSession` objects; owns key lookup callback wired to `KeyProvider`
- `KeyProvider` — SSH key entries (path + optional passphrase)
- `PortForwardProvider` — local/remote/dynamic tunnel configs
- `SnippetProvider` — reusable command snippets

**Services** (`app/lib/services/`):
- `SshService` — owns `SSHClient` and `SSHSession` maps keyed by host/session ID; handles connect, shell, exec, sftp, disconnect
- `StorageService` — host list stored as JSON in `SharedPreferences`; passwords/passphrases stored per-key in `FlutterSecureStorage` (`pw_<hostId>`, `pp_<keyId>`)

**Key models** (`app/lib/models/`):
- `Host` — connection profile (host, port, username, `AuthType`)
- `SshSession` — wraps an xterm `Terminal` object; bridges `dartssh2` shell I/O to the widget
- `SshKeyEntry`, `PortForward`, `Snippet`

**UI entry point:** `app/lib/main.dart` bootstraps all providers and renders `MainScreen`. The app is dark-only (`ThemeMode.dark`).
