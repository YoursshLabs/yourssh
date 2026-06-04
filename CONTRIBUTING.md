# Contributing to YourSSH

Thank you for your interest in contributing! YourSSH is an open-source SSH client for macOS, Windows, and Linux built with Flutter, and contributions of all kinds are welcome — bug reports, feature ideas, documentation, and code.

Please note that this project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold it.

## Ways to Contribute

- **Report a bug** — open a [Bug Report](https://github.com/YoursshLabs/yourssh/issues/new?template=bug_report.md)
- **Suggest a feature** — open a [Feature Request](https://github.com/YoursshLabs/yourssh/issues/new?template=feature_request.md)
- **Ask a question** — open a [Question](https://github.com/YoursshLabs/yourssh/issues/new?template=question.md) or use [Discussions](https://github.com/YoursshLabs/yourssh/discussions)
- **Report a security vulnerability** — please follow our [Security Policy](SECURITY.md) and **never** open a public issue
- **Submit code** — see below

For larger changes, please open an issue first to discuss the approach before investing significant time.

## Development Setup

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.x stable (Dart SDK `^3.12.0`)
- Platform toolchain:
  - **macOS:** Xcode
  - **Windows:** Visual Studio with the "Desktop development with C++" workload
  - **Linux:** `clang`, `cmake`, `ninja-build`, and GTK3 development headers (`libgtk-3-dev`)

### Build & Run

```bash
git clone https://github.com/YoursshLabs/yourssh.git
cd yourssh/app
flutter pub get
flutter run -d macos     # or: -d windows / -d linux
```

### Lint & Test

```bash
cd app
flutter analyze          # must report no new warnings
flutter test             # all tests must pass
flutter test test/services/sync_service_test.dart   # single test file
flutter test --name "pattern"                       # filter by test name
```

## Project Layout

This is a monorepo:

| Path | Description |
| --- | --- |
| `app/` | The Flutter app (the active codebase) |
| `packages/dartssh2` | Local fork of `dartssh2` (SSH/SFTP), used via `dependency_overrides` |
| `packages/flutter_pty` | Local fork of `flutter_pty` (local terminal PTY) |
| `packages/xterm` | Local fork of `xterm` (terminal emulator widget) |
| `packages/yourssh_plugin_api` | Abstract plugin interface for compile-time Dart plugins |
| `packages/yourssh_devops`, `yourssh_web_tools`, `yourssh_snippets` | Built-in Dart plugins |
| `packages/yourssh_script_engine` | Runtime JS plugin engine (QuickJS) |
| `core/` | Rust core — **not currently used at runtime** |

> **Note on local forks:** `dartssh2`, `flutter_pty`, and `xterm` are forked to carry specific patches. If your change touches one of these packages, explain in the PR why it can't be solved in `app/` and reference the upstream issue where applicable.

## Branching & Pull Requests

- `develop` is the working branch — **target your PRs at `develop`**.
- `master` is the release branch; release PRs are handled by maintainers.

### PR Guidelines

1. **Title** must follow [Conventional Commits](https://www.conventionalcommits.org/): `feat(scope): ...`, `fix(scope): ...`, `docs: ...`, `test: ...`, `refactor: ...`
2. **Fill in the PR template** — summary, changes, type, and how it was tested.
3. **Code, comments, and docs are written in English.**
4. **Cover new or changed behavior with tests.** Pure logic should be unit-tested; see `app/test/` for existing patterns.
5. **Run `flutter analyze` and `flutter test`** locally before pushing — CI runs both on every PR.
6. **Include screenshots** for UI changes (the app is dark-only; see `app/lib/theme/app_theme.dart`).
7. **Never include secrets**, credentials, hostnames, or personal data in code, tests, or screenshots.

### Commit Messages

Follow Conventional Commits for individual commits as well, e.g.:

```
feat(sftp): add drag-and-drop upload to remote panel
fix(terminal): preserve scrollback on reconnect
```

## Code Style

- Match the surrounding code — naming, structure, and comment density.
- Keep widgets, providers, and services in their established directories (`app/lib/widgets/`, `app/lib/providers/`, `app/lib/services/`).
- Prefer small, focused units: pure logic separated from Flutter/IO so it can be unit-tested.
- State management uses `provider` (`ChangeNotifier`) — follow the existing provider patterns.

## Release Process (Maintainers)

Releases are cut from `master` via release PRs, which additionally require a `CHANGELOG.md` update, a version bump in `app/pubspec.yaml`, and refreshed docs (`README.md`, `docs/roadmap.md`, wiki release notes). Contributors don't need to do any of this — it's handled at release time.

---

Thanks again for contributing! 🚀
