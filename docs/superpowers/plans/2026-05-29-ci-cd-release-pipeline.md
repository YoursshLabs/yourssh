# CI/CD Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a GitHub Actions workflow that automatically builds YourSSH for macOS and Windows on push to `master`, then publishes a GitHub Release with 2 attached files.

**Architecture:** A single workflow file (`.github/workflows/release.yml`) with 3 jobs: `build-macos` and `build-windows` run in parallel on their respective runners, then `release` collects the artifacts and creates the GitHub Release. Version is read from `app/pubspec.yaml`.

**Tech Stack:** GitHub Actions, `subosito/flutter-action@v2`, `actions/upload-artifact@v4`, `actions/download-artifact@v4`, `softprops/action-gh-release@v2`

---

## File Structure

- **Create:** `.github/workflows/release.yml` — the entire CI/CD pipeline

---

### Task 1: Create the workflow directory and file

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the `.github/workflows/` directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create `release.yml` with the full content**

Create file `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    branches:
      - master

permissions:
  contents: write

jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        working-directory: app
        run: flutter pub get

      - name: Build macOS
        working-directory: app
        run: flutter build macos --release

      - name: Zip macOS app
        run: zip -r YourSSH-macos.zip "app/build/macos/Build/Products/Release/YourSSH.app"

      - uses: actions/upload-artifact@v4
        with:
          name: macos-build
          path: YourSSH-macos.zip

  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        working-directory: app
        run: flutter pub get

      - name: Build Windows
        working-directory: app
        run: flutter build windows --release

      - name: Zip Windows build
        run: Compress-Archive -Path "app\build\windows\x64\runner\Release\*" -DestinationPath "YourSSH-windows.zip"

      - uses: actions/upload-artifact@v4
        with:
          name: windows-build
          path: YourSSH-windows.zip

  release:
    runs-on: ubuntu-latest
    needs: [build-macos, build-windows]
    steps:
      - uses: actions/checkout@v4

      - name: Extract version from pubspec.yaml
        id: version
        run: |
          VERSION=$(grep '^version:' app/pubspec.yaml | sed 's/^version:[[:space:]]*//')
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - uses: actions/download-artifact@v4
        with:
          name: macos-build

      - uses: actions/download-artifact@v4
        with:
          name: windows-build

      - uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.version.outputs.version }}
          name: YourSSH v${{ steps.version.outputs.version }}
          generate_release_notes: true
          files: |
            YourSSH-macos.zip
            YourSSH-windows.zip
```

- [ ] **Step 3: Verify YAML syntax is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML OK"
```

Expected output: `YAML OK`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: add GitHub Actions CI/CD pipeline for macOS and Windows release"
```

---

### Task 2: Push and verify the pipeline runs correctly

- [ ] **Step 1: Push to master**

```bash
git push origin master
```

- [ ] **Step 2: Monitor Actions on GitHub**

Go to the **Actions** tab on the GitHub repo → select the latest workflow run → verify:
- `build-macos` job completes successfully (approximately 8-12 minutes)
- `build-windows` job completes successfully (approximately 8-12 minutes)
- `release` job runs after both complete

- [ ] **Step 3: Verify the GitHub Release is created**

Go to the **Releases** tab on the GitHub repo → verify:
- Release named `YourSSH v0.1.0+1` (or the current version in pubspec.yaml)
- Includes attached files `YourSSH-macos.zip` and `YourSSH-windows.zip`
- Release notes are auto-generated from commit messages

---

## Common Troubleshooting

**macOS build error "Xcode not found":**
- `macos-latest` runner has Xcode pre-installed, but if it fails add this step:
```yaml
- uses: maxim-lobanov/setup-xcode@v1
  with:
    xcode-version: latest-stable
```

**Windows build error "Visual Studio not found":**
- `windows-latest` runner has VS Build Tools pre-installed. If still failing, add:
```yaml
- name: Setup VS
  uses: microsoft/setup-msbuild@v2
```

**`release` job error "tag already exists":**
- `softprops/action-gh-release@v2` will update the release if the tag already exists — no action needed.
- If you want to avoid junk releases, consider switching the trigger to push tag `v*` later.

**Version extraction produces wrong output:**
- Test locally: `grep '^version:' app/pubspec.yaml | sed 's/^version:[[:space:]]*//'`
- Expected output: `0.1.0+1`
