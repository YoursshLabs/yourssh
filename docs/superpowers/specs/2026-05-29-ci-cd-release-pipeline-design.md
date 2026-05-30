# CI/CD Release Pipeline Design

**Date:** 2026-05-29  
**Status:** Approved

## Overview

Set up a GitHub Actions pipeline to automatically build the YourSSH application for macOS and Windows when code is pushed to the `master` branch, then create a GitHub Release with the attached files.

## Trigger

- **Event:** `push` to the `master` branch
- Does not trigger on pushes to other branches

## Workflow Structure

A single file: `.github/workflows/release.yml`  
Three jobs run in order: `build-macos` and `build-windows` in parallel → `release`.

### Job 1: `build-macos`

- **Runner:** `macos-latest`
- **Steps:**
  1. Checkout code (`actions/checkout@v4`)
  2. Setup Flutter (`subosito/flutter-action@v2`, channel `stable`)
  3. Install dependencies: `flutter pub get` in the `app/` directory
  4. Build: `flutter build macos --release`
  5. Zip artifact: compress `app/build/macos/Build/Products/Release/YourSSH.app` → `YourSSH-macos.zip`
  6. Upload artifact: `actions/upload-artifact@v4` named `macos-build`

### Job 2: `build-windows`

- **Runner:** `windows-latest`
- **Steps:**
  1. Checkout code (`actions/checkout@v4`)
  2. Setup Flutter (`subosito/flutter-action@v2`, channel `stable`)
  3. Install dependencies: `flutter pub get` in the `app/` directory
  4. Build: `flutter build windows --release`
  5. Zip artifact: compress the `app/build/windows/x64/runner/Release/` directory → `YourSSH-windows.zip`
  6. Upload artifact: `actions/upload-artifact@v4` named `windows-build`

### Job 3: `release`

- **Runner:** `ubuntu-latest`
- **needs:** `[build-macos, build-windows]`
- **Steps:**
  1. Checkout code
  2. Read version from `app/pubspec.yaml` using `grep` + `sed`, set into env var `VERSION` (format `0.1.0+1`)
  3. Download artifacts `macos-build` and `windows-build` (`actions/download-artifact@v4`)
  4. Create GitHub Release named `v$VERSION` using `softprops/action-gh-release@v2`:
     - Tag: `v$VERSION`
     - Title: `YourSSH v$VERSION`
     - Body: auto-generated from commit messages
     - Files: `YourSSH-macos.zip`, `YourSSH-windows.zip`
  5. Use the default `GITHUB_TOKEN` (no additional secrets required)

## Versioning

- Version read from the `version:` line in `app/pubspec.yaml`
- Regex: `version:\s*(.+)` → captures the full value (e.g. `0.1.0+1`)
- Release tag: `v0.1.0+1`
- If the same version is pushed multiple times, `action-gh-release` will **overwrite** the existing release with the same tag

## Artifacts

| File | Contents | Platform |
|------|----------|----------|
| `YourSSH-macos.zip` | `yourssh.app` bundle | macOS 12+ |
| `YourSSH-windows.zip` | `Release/` directory with `.exe` and DLLs | Windows 10/11 |

## Out of Scope

- Code signing / notarization (macOS Gatekeeper bypass on the user side)
- MSIX / installer for Windows
- Automated tests before building
- Flutter SDK caching (can be added later to speed up builds)

## Permissions

The workflow requires `write` permission for `contents` to create a release. Add to workflow:

```yaml
permissions:
  contents: write
```

## New Files

- `.github/workflows/release.yml`
