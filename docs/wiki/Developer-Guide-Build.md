# Build

YourSSH targets macOS, Windows, and Linux via Flutter.

## Prerequisites

- **Flutter 3.x** — install via [flutter.dev](https://flutter.dev/docs/get-started/install)
- Run `flutter doctor` and resolve any issues before building
- Platform-specific tooling:
  - macOS: Xcode 15+
  - Windows: Visual Studio 2022 with "Desktop development with C++" workload
  - Linux: `clang cmake ninja-build pkg-config libgtk-3-dev`

## Run in Development

```bash
# macOS
cd app && flutter run -d macos

# Windows
cd app && flutter run -d windows

# Linux
cd app && flutter run -d linux
```

## Build Release

```bash
# macOS — outputs app/build/macos/Build/Products/Release/YourSSH.app
cd app && flutter build macos

# Windows — outputs app/build/windows/x64/runner/Release/
cd app && flutter build windows

# Linux — outputs app/build/linux/x64/release/bundle/
cd app && flutter build linux
```

## Lint & Tests

```bash
# Static analysis
cd app && flutter analyze

# All tests
cd app && flutter test

# Single test file
cd app && flutter test test/services/sync_service_test.dart

# Filter by test name pattern
cd app && flutter test --name "SyncService"
```

## Local Package Dependencies

`app/pubspec.yaml` uses `dependency_overrides` to pull the local forks of `dartssh2`, `flutter_pty`, and `xterm` plus all `yourssh_*` packages:

```yaml
dependency_overrides:
  dartssh2:
    path: ../packages/dartssh2
  flutter_pty:
    path: ../packages/flutter_pty
  xterm:
    path: ../packages/xterm
  yourssh_plugin_api:
    path: ../packages/yourssh_plugin_api
  # … etc
```

If you modify a package in `packages/`, the app picks up the change immediately — no publish step needed.

## Rust Core (Inactive)

The `core/` Rust library is not linked into the app at runtime. If you want to build it:

```bash
make setup   # Install Rust targets + xcodegen
make core    # Build universal .a + Swift bindings
make clean   # Remove Rust artifacts
```

## CI / Release

GitHub Actions workflows live in `.github/workflows/`. The `release.yml` workflow builds for all three platforms and attaches artifacts to the GitHub Release on tag push.

## Related Pages

- [Architecture](Developer-Guide-Architecture) — understand the codebase before modifying
- [Contributing](Developer-Guide-Contributing) — PR and release workflow
