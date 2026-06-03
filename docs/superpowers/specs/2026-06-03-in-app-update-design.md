# In-App Update (Assisted Download) — Design

**Date:** 2026-06-03
**Status:** Approved (design), pending implementation plan
**Scope:** `app/` (Flutter desktop: macOS, Windows, Linux)

## Goal

Notify the user inside the app when a newer stable release is available, then let
them download the correct artifact for their OS/architecture and launch the
installer with one click. The app is **not** Apple-notarized and **not**
Windows code-signed, so the design avoids fragile silent self-replacement and
uses an **assisted download** flow instead.

## Decisions (locked)

- **Update level:** Assisted download. App checks, shows a banner, downloads the
  right artifact on demand, then hands off to the OS installer. The user
  confirms the final install step. No silent swap-and-relaunch.
- **Check trigger:** On app launch (debounced to at most once per 24h) **plus** a
  manual "Check for updates" button in Settings (manual always runs, ignores
  debounce).
- **UI surface:** A dismissible banner at the top of `MainScreen` when an update
  is available, plus a detail section in the Settings screen.
- **Release channel:** Stable only. Uses GitHub's `releases/latest` endpoint,
  which already excludes drafts and pre-releases.
- **No new dependencies.** All required packages already exist: `http`,
  `package_info_plus`, `path_provider`, `url_launcher`, `local_notifier`.
  Semver comparison is a small pure function (no `pub_semver`).

## Source of truth

Releases are published to GitHub (`YoursshLabs/yourssh`) with tags `vX.Y.Z`.
Latest stable: `GET https://api.github.com/repos/YoursshLabs/yourssh/releases/latest`
with header `Accept: application/vnd.github+json`. Unauthenticated; rate limit
(60 req/hr/IP) is a non-issue given launch + 24h debounce + manual.

Release asset filename patterns (from `.github/workflows/release.yml`):

| Platform | Arch  | Asset pattern (preferred → fallback) |
|----------|-------|--------------------------------------|
| macOS    | arm64 | `YourSSH-{v}-macOS-arm64.dmg` |
| Windows  | x64   | `YourSSH.Setup.{v}-Windows-x64.exe` → `YourSSH-{v}-Windows-x64.exe` |
| Windows  | arm64 | `YourSSH.Setup.{v}-Windows-arm64.exe` → `YourSSH-{v}-Windows-arm64.exe` |
| Linux    | amd64 | `yourssh_{v}_amd64.deb` → `YourSSH-{v}-Linux-x86_64.tar.gz` |
| Linux    | arm64 | `yourssh_{v}_arm64.deb` → `YourSSH-{v}-Linux-arm64.tar.gz` |

There is no macOS x64 (Intel) artifact. On an Intel Mac, asset selection returns
null and the flow falls back to opening the Releases page in the browser.

## Architecture

```
launch (post-first-frame) ─┐
Settings "Check" button ────┴─► UpdateProvider.checkForUpdates({manual})
       │  auto: skip if <24h since last check; manual: always run
       ▼
   UpdateService.fetchLatestRelease()  ──► GitHub releases/latest (stable)
       │
       ▼
   UpdateService.isNewerVersion(current, latest)
       │  true ──► status=available ──► banner + Settings section show
       │  user clicks "Update"
       ▼
   assetForPlatform(release, os, arch)
       │  null ──► open release.htmlUrl in browser (fallback)
       ▼
   downloadAsset(asset, onProgress) ──► file in Downloads dir
       │  status=readyToInstall
       ▼
   launchInstaller(file)  ──► hand off to OS
```

### Components (new files)

**`app/lib/models/app_release.dart`**
- `AppRelease` — `{ String version; String tagName; String name; String notes;
  String htmlUrl; DateTime? publishedAt; List<ReleaseAsset> assets; }` with
  `AppRelease.fromJson(Map)`. `version` is `tagName` with the leading `v`
  stripped. `notes` is the release body (markdown).
- `ReleaseAsset` — `{ String name; String downloadUrl; int size; }` from each
  entry in the API `assets[]` (`browser_download_url`, `size`).
- `enum UpdateStatus { idle, checking, upToDate, available, downloading,
  readyToInstall, error }`.

**`app/lib/services/update_service.dart`** (no Flutter imports; unit-testable)
- `Future<AppRelease> fetchLatestRelease()` — HTTP GET + parse; throws a typed
  error on network failure, non-200 (incl. 403 rate limit), or malformed JSON.
- `bool isNewerVersion(String current, String latest)` — pure. Strips leading
  `v`, drops any pre-release/build suffix (`-`, `+`), compares numeric
  `major.minor.patch`. Missing segments treated as 0. Returns false on equal or
  unparseable input (fail closed: never prompt to "update" to an older/equal
  version).
- `ReleaseAsset? assetForPlatform(AppRelease release, {required String os,
  required String arch})` — matches by the table above; returns null if no
  match (caller falls back to browser).
- `String currentArch()` — macOS: `'arm64'` (only arch shipped); Windows: read
  `PROCESSOR_ARCHITECTURE` env (`ARM64` → `arm64`, else `x64`); Linux: `uname -m`
  (`aarch64`/`arm64` → `arm64`, else `amd64`).
- `Future<File> downloadAsset(ReleaseAsset asset, {required void
  Function(double) onProgress, Directory? targetDir})` — streamed download into
  the Downloads directory (`path_provider`), reports `0.0..1.0`. Cleans up a
  partial file on failure.
- `Future<void> launchInstaller(File file)` — platform dispatch:
  - **macOS:** `xattr -dr com.apple.quarantine <file>` (best-effort, ignore
    failure), then `open <file>` to mount the DMG. User drags app to
    /Applications.
  - **Windows:** `Process.start(file.path, [])` to run the installer `.exe`
    (SmartScreen may warn; user clicks "Run anyway").
  - **Linux:** `xdg-open <file>` to hand the `.deb`/`.tar.gz` to the desktop's
    package/archive handler.

**`app/lib/providers/update_provider.dart`** (`ChangeNotifier`)
- State: `UpdateStatus status`, `AppRelease? latestRelease`,
  `String currentVersion` (from `package_info_plus`), `double downloadProgress`,
  `String? dismissedVersion`, `String? errorMessage`, `File? downloadedFile`.
- `Future<void> checkForUpdates({bool manual = false})` — reads
  `last_update_check` from `SharedPreferences`; if not `manual` and <24h since
  last check, returns without calling the network. Sets `status=checking`,
  fetches, compares, sets `available`/`upToDate`/`error`, stamps
  `last_update_check` on completion.
- `Future<void> downloadAndInstall()` — resolves asset (fallback: open
  `htmlUrl`), sets `status=downloading`, downloads with progress, sets
  `readyToInstall`, then calls `launchInstaller`.
- `void dismiss()` — sets `dismissedVersion = latestRelease.version`, persists to
  `SharedPreferences`; banner hides for that version only.
- `bool get showBanner` — `status == available && latestRelease.version !=
  dismissedVersion`.

**`app/lib/widgets/update_banner.dart`**
- Dismissible banner mounted at the top of `MainScreen` body, shown when
  `UpdateProvider.showBanner`. Text "New version vX.Y.Z available". Actions:
  **Update** (→ `downloadAndInstall`), **Details** (→ open Settings update
  section), close (→ `dismiss`). Styled with `AppColors`.

**Settings update section** (`app/lib/widgets/settings/update_settings_section.dart`,
or inline in the existing settings screen — match existing pattern)
- Shows current version, latest version, release notes, and the controls:
  **Check for updates** button (`checkForUpdates(manual: true)`), a progress bar
  while `downloading`, and a **Download & install** button. Error state shows a
  retry affordance.

### Wiring (`app/lib/main.dart`)
- Instantiate `UpdateService` and `UpdateProvider`; add `UpdateProvider` to the
  `MultiProvider` list.
- After the first frame (`WidgetsBinding.instance.addPostFrameCallback`), call
  `checkForUpdates()` (auto, debounced).

## Error handling (no silent failures)

- Network failure / non-200 / 403 rate limit → `status=error`, `errorMessage`
  set; banner does **not** show; Settings shows "Couldn't check for updates —
  try again". No crash, no throw to the UI layer.
- No matching asset for OS/arch (e.g. Intel Mac) → open `release.htmlUrl` via
  `url_launcher`; surface a short note that a manual download is needed.
- Download failure → `status=error`, partial file removed, retry allowed.
- `launchInstaller` failure → fall back to revealing the file / opening the
  Releases page; report the error.

## Testing

Unit tests in `app/test/services/update_service_test.dart`:
- `isNewerVersion`: equal versions → false; patch/minor/major bumps → true;
  older → false; `v` prefix handled; pre-release/build suffix ignored;
  unparseable → false.
- `assetForPlatform`: correct asset per (os, arch) from a sample `releases/latest`
  JSON fixture; preferred-vs-fallback ordering; null when no match (macOS x64).
- `AppRelease.fromJson`: parses version (strips `v`), notes, htmlUrl, and the
  assets list from a fixture.

Provider debounce logic is covered lightly (inject a clock or `SharedPreferences`
mock); full network/IO paths are not unit-tested (would need integration
harness — out of scope here).

## Out of scope (YAGNI)

- Silent auto-replace and auto-relaunch.
- Background polling timer.
- Pre-release / beta opt-in channel.
- Delta/differential updates.
- Code signing / notarization (separate, larger effort).
