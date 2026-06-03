# SFTP View + Open With — Design

**Date:** 2026-06-03

## Goal

Upgrade the SFTP file context menu from a single "Open / Edit / Open with external app" set of actions to a richer, more natural model:

- **View** — read-only in-app preview (no accidental edits)
- **Edit** — in-app editor (current behaviour, unchanged)
- **Open with ▶** — submenu listing apps that can open this file type, plus "Choose…" as a fallback; replaces "Open with external app"

All three platforms (macOS, Linux, Windows) are fully supported.

## Context menu — final shape

| Entry | Applies to | Behaviour |
|---|---|---|
| **Enter** | Directories | Navigate into directory |
| **View** | Files | Open `CodeEditorScreen` in `readOnly` mode |
| **Edit** | Files | Open `CodeEditorScreen` in editable mode (current) |
| **Open with ▶** | Files | Show app-discovery submenu |
| *(divider)* | | |
| **Rename** | Both | — |
| **Delete** | Both | — |
| *(divider)* | | |
| **Copy path** | Both | — |

## Part 1 — View (read-only mode)

### `CodeEditorScreen` changes

Add `readOnly: bool = false` constructor parameter. When `true`:

- AppBar: save button replaced by a `lock` icon badge (non-interactive).
- No `CallbackShortcuts` for Ctrl/Cmd+S.
- No `_isDirty` tracking; `onChanged` is a no-op.
- No `PopScope` / discard dialog.
- Fallback `TextField` has `readOnly: true`.
- Webview path: after `loadContent`, call `setReadOnly(true)` via the existing JS channel (add a one-liner to `assets/monaco_editor.html`).

### Context menu change

Rename current "Open" action → **View** (icon `Icons.visibility_outlined`).
Keep **Edit** as-is (icon `Icons.edit_outlined`).
Both are shown only for files (not directories). Directory action stays **Enter**.

## Part 2 — "Open with ▶" submenu

### Data model

```dart
class AppOption {
  final String name;
  final String executablePath; // absolute path to app/exe/binary
  final String? iconPath;      // platform-native icon path (may be null)
  final bool isDefault;
}
```

### `AppDiscoveryService`

New service: `app/lib/services/app_discovery_service.dart`.

**Interface:**
```dart
Future<List<AppOption>> getAppsFor(String filePath);
```

Results are **cached per file extension** in a `Map<String, List<AppOption>>` so repeated right-clicks on `.txt` files don't re-scan. Cache is invalidated on service `dispose()`.

**Platform implementations** — selected at runtime via `Platform.isMacOS / isLinux / isWindows`:

#### macOS — Swift method channel

A new Flutter method channel `yourssh/app_discovery` is registered in
`app/macos/Runner/AppDelegate.swift`:

```swift
// Channel name: "yourssh/app_discovery"
// Method: "getAppsFor" { "path": String } → [[name, bundleId, execPath, iconPath?], ...]
let channel = FlutterMethodChannel(
    name: "yourssh/app_discovery",
    binaryMessenger: controller.engine.binaryMessenger)
channel.setMethodCallHandler { call, result in
    guard call.method == "getAppsFor",
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented); return
    }
    let fileURL = URL(fileURLWithPath: path)
    let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
    let mapped = apps.map { appURL -> [String] in
        let bundle = Bundle(url: appURL)
        let name = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let bundleId = bundle?.bundleIdentifier ?? ""
        let iconPath = (bundle?.resourceURL?.appendingPathComponent(
            bundle?.infoDictionary?["CFBundleIconFile"] as? String ?? "").path) ?? ""
        return [name, bundleId, appURL.path, iconPath]
    }
    result(mapped)
}
```

The `executablePath` for macOS is the `.app` bundle path; launching uses
`Process.run('open', ['-a', executablePath, filePath])`.

#### Linux — Pure Dart

1. `Process.run('xdg-mime', ['query', 'filetype', filePath])` → MIME type string.
2. Scan `~/.local/share/applications/` and `/usr/share/applications/` for `.desktop` files.
3. Parse each file: collect those whose `MimeType=` field contains the detected MIME type.
4. Extract `Name=`, `Exec=` (strip `%f/%u/%F/%U` placeholders → actual binary path).
5. Mark entry as `isDefault` if it matches `xdg-mime query default <mimeType>`.

Launching: `Process.run(executablePath, [filePath])`.

#### Windows — PowerShell + registry

```
PowerShell -NoProfile -Command
  "$ext = [System.IO.Path]::GetExtension('<path>');
   $handlers = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\OpenWithList' -EA SilentlyContinue);
   $handlers.PSObject.Properties | Where-Object { $_.Name -match '^[a-z]$' } |
   ForEach-Object { $_.Value }"
```

Returns a list of `.exe` file names → resolve to full paths via
`where.exe <name>` or `(Get-Command <name>).Source`.

Display name: read `FileDescription` from the `.exe` via
`[System.Diagnostics.FileVersionInfo]::GetVersionInfo(path).FileDescription`.

Fallback if PowerShell query returns empty: use `cmd /c assoc .<ext>` → `ftype` to get at least the default handler.

Launching: `Process.run(executablePath, [filePath])`.

### Submenu UI

Flutter has no native cascading menu widget. Implementation:

1. "Open with ▶" is a `PopupMenuItem` with a trailing `Icons.chevron_right`.
2. On tap: call `AppDiscoveryService.getAppsFor(downloadedTmpPath)` (downloads file first if not yet downloaded, or uses a stub path with just the extension for fast lookup).
3. Call `showMenu` a second time, positioned to the right of the "Open with" item using the `RelativeRect` from `localToGlobal` of the item's `BuildContext`.
4. Each submenu item shows app name (+ "Default" chip if `isDefault`). Optional: platform icon via `Image.file(iconPath)` with fallback to `Icons.apps`.
5. Last item, separated by a divider: **Choose…**

### "Choose…"

Opens `file_selector` (`FileSelectorPlatform`) to let the user pick an executable:

| Platform | Filter | Launch |
|---|---|---|
| macOS | `*.app` in `/Applications` | `open -a <appPath> <filePath>` |
| Linux | No filter (any file) | `Process.run(execPath, [filePath])` |
| Windows | `*.exe` | `Process.run(exePath, [filePath])` |

`file_selector` is not yet in `pubspec.yaml` — add `file_selector: ^0.9.0`.

### Integration with ExternalEditService

After the user picks any app (from list or Choose), the flow is:

1. `ExternalEditService.openExternalWith(host, entry, appPath)` — new overload that accepts an explicit `appPath`.
2. Internally: same download → per-session temp dir → watch loop as today.
3. Launch step replaced with platform-specific "open with app" call above instead of `launchUrl`.

`ExternalEditService` gets a new `openExternalWith` method; existing `openExternal` (default app via `launchUrl`) is kept for backward compatibility.

## Error handling

- `AppDiscoveryService` returns `[]` on any platform error (no crash); "Open with ▶" shows only "Choose…" in that case.
- Method channel unavailable (e.g., running tests): return empty list.
- "Choose…" picker cancelled: no-op.
- Launch failure: snackbar (same pattern as existing `_openExternal`).

## Testing

- Unit: `AppDiscoveryService` on Linux (pure Dart, can test `.desktop` parsing with fixture files). macOS and Windows implementations return mocked channel/process results.
- Widget: `SftpEntryContextMenu` renders "Open with ▶" for files; tapping it calls `onOpenWith`.
- Widget: `CodeEditorScreen` with `readOnly: true` — save button absent, `TextField.readOnly == true`.
- `ExternalEditService.openExternalWith` — same fake-transfer pattern as existing tests, but verify launch was called with the given `appPath`.

## Out of scope

- App icons rendered in the submenu (icon path is plumbed through but rendering is best-effort; fallback to generic icon is always acceptable).
- Remembering the last-used app per file type (can be a future setting).
- Sandbox / entitlement changes for macOS App Store distribution.
