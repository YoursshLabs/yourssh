# SFTP Local-Remote Dual Panel Design

**Date:** 2026-05-29  
**Status:** Approved

## Goal

Replace the current dual-remote SFTP view (both panels show SSH hosts) with a local-remote layout: left panel always shows the local machine's filesystem; right panel shows a remote SSH host (with an empty state until one is selected).

## Architecture

### New files

| File | Purpose |
|------|---------|
| `app/lib/widgets/local_file_panel.dart` | Local filesystem browser widget |
| `app/lib/providers/local_file_panel_provider.dart` | State: current path, entries, selection, filter string |
| `app/lib/models/local_entry.dart` | `LocalEntry` model backed by `dart:io` |

### Modified files

| File | Change |
|------|--------|
| `dual_panel_sftp_screen.dart` | Left = `LocalFilePanel`, right = `SftpPanel` (nullable host); adds center transfer bar |
| `sftp_panel.dart` | `host` becomes nullable; empty-state rendered when `null` |
| `sftp_transfer_service.dart` | Add `copyLocalToRemote` and `copyRemoteToLocal` methods |

### `LocalEntry` model fields

| Field | Type | Source |
|-------|------|--------|
| `name` | `String` | `FileSystemEntity.uri.pathSegments.last` |
| `path` | `String` | `FileSystemEntity.path` |
| `isDirectory` | `bool` | `FileSystemEntity is Directory` |
| `size` | `int` | `FileStat.size` |
| `modifiedAt` | `DateTime` | `FileStat.modified` |
| `permissions` | `String` | `FileStat.modeString()` |

### Data flow

```
LocalFilePanel
  └── LocalFilePanelProvider (ChangeNotifier)
        └── dart:io Directory.list() → List<LocalEntry>

SftpPanel (right, unchanged logic)
  └── SftpPanelProvider
        └── SftpTransferService → SshService → dartssh2

DualPanelSftpScreen
  ├── LocalFilePanel  (left, always local)
  ├── TransferBar     (center strip ~28px, ←/→ buttons)
  └── SftpPanel       (right, host nullable)
```

## Local Panel UI

### Header bar
- Left: "Local" label
- Right: "Filter" button (toggles search field) + "Actions" dropdown

### Actions menu
- **New Folder** — inline name input, creates via `Directory.create()`
- **Rename** — renames the selected item via `FileSystemEntity.rename()`
- **Delete** — deletes selected items after a confirmation dialog

### Filter
- Toggling "Filter" shows a text field below the header
- Entry list filters in real-time by filename (case-insensitive contains)
- Closing the filter resets the list

### Breadcrumb bar
- `< >` back/forward navigation arrows
- Path segments as tappable chips — tapping jumps to that directory
- Root label: "Macintosh HD" on macOS, drive letter on Windows

### File list
- Columns: Name (icon + permission string subtitle), Date Modified, Size, Kind
- Folders sorted first
- Single click = select; `Cmd/Ctrl+click` = multi-select
- Right-click context menu: Rename, Delete

## Remote Panel Empty State

When `host` is `null`:
- Large muted folder icon
- Title: "Connect to host"
- Subtitle: "Start by connecting to a saved host to manage your files with SFTP."
- "Select host" button → opens `_HostPickerDialog`

## Transfer Bar (center strip)

- `→` button: upload selected local file(s) to current remote directory
- `←` button: download selected remote file(s) to current local directory
- Both disabled when the relevant panel has no selection or remote is disconnected
- Active transfer shows a `LinearProgressIndicator` above the bar

## Drag and Drop

- Drag local entry → drop onto remote panel → upload
- Drag remote entry → drop onto local panel → download
- Implemented with Flutter `Draggable` / `DragTarget`

## Transfer Implementation

| Direction | Implementation |
|-----------|---------------|
| Local → Remote | Read bytes from `dart:io File.readAsBytes()`, write via `sftp.open()` + `writeBytes()` |
| Remote → Local | `sftp.open()` + `readBytes()`, write to `File(localPanel.currentPath / entry.name)` |

## Error Handling

- Local I/O errors → inline error state (icon + message + retry button) inside the local panel
- SFTP transfer errors → `SnackBar` with error message (non-fatal)
- Rename/delete errors → `SnackBar` with OS error message
- No silent failures — all errors surface to the user

## Out of Scope

- Multi-file drag (drag one file at a time in this iteration)
- Progress per-file for large transfers (single `LinearProgressIndicator` for the active transfer)
- The old dual-remote mode (both panels pointing to SSH hosts) is removed entirely
