# Entry Context Menu Redesign — Design

**Date:** 2026-06-05
**Status:** Approved

## Goal

Unify and extend the right-click context menu for file/folder entries across both
panels of the dual-panel SFTP screen (remote SFTP panel and local file panel),
matching the reference design:

- **Folder menu:** Open · Copy to target directory · Rename · Delete · Refresh ·
  New Folder · Edit Permissions
- **File menu:** same, plus Open / Open with… at the top

Existing items not in the reference (View, Edit, Copy path) are kept.

## Current state

- `SftpPanel` uses `SftpEntryContextMenu` (MenuAnchor-based, hover-cascading
  "Open with" submenu): Enter / View / Edit / Open with / Rename / Delete /
  Copy path.
- `LocalFilePanel` uses a plain `showMenu` with only Rename / Delete.
- `DualPanelSftpScreen` already owns the full transfer matrix
  (`_transfer`: localCopy / upload / download / remoteRelay), New Folder
  dialogs exist in both panels, Refresh exists on the path bar.
- No chmod anywhere; `SftpEntry` does not carry permission bits
  (`LocalEntry.permissions` already exists as an rwx string).
- dartssh2 fork exposes `SftpClient.setStat(path, SftpFileAttrs)` — chmod is
  available.

## Decisions (user-confirmed)

1. The new menu applies to **both** panels. "Edit Permissions" is hidden on
   the local panel on Windows (no chmod).
2. **Keep all existing items** (View, Edit, Copy path) in addition to the new
   ones.
3. Permissions dialog uses a **9-checkbox rwx grid two-way synced with an
   octal field**; directories get an "Apply recursively" option.
4. "Copy to target directory" is **disabled with a visible reason** when not
   applicable (no target panel; folder between two remote hosts).
5. The folder open item is relabeled **"Enter" → "Open"** for consistency.

## Design

### 1. Shared menu widget

Generalize `sftp_entry_context_menu.dart` into `entry_context_menu.dart`
(`EntryContextMenu`), used by both panels. MenuAnchor styling stays as-is;
the local panel drops its `showMenu` implementation.

Menu layout (`│` = divider):

- **File:** Open · View · Edit · Open with ▸ │ Copy to target directory ·
  Rename · Delete (red) │ Refresh · New Folder · Edit Permissions │ Copy path
- **Folder:** Open │ Copy to target directory · Rename · Delete (red) │
  Refresh · New Folder · Edit Permissions │ Copy path

"Open" performs the default tap action: folders navigate into the directory;
remote files open in the in-app editor with the existing binary/too-large
fallback to an external app; local files open with the OS default application.

New constructor parameters (in addition to the existing ones):

- `onCopyToTarget: VoidCallback?`
- `copyToTargetDisabledReason: String?` — when non-null the item renders
  dimmed with the reason as a trailing hint
- `onRefresh: VoidCallback`
- `onNewFolder: VoidCallback`
- `onEditPermissions: VoidCallback?` — null hides the item (local panel on
  Windows)

The widget stays entry-type-agnostic: it takes a generic display name/path and
`isDirectory` flag (or keeps taking both `SftpEntry`/`LocalEntry` via a small
adapter — implementation detail), so both panels can use it.

### 2. Copy to target directory

`DualPanelSftpScreen` passes a copy-to-target callback and an availability
resolver down to each slot's panel:

- Other slot has no source → disabled, reason "No target panel".
- Directory between two remote hosts (remoteRelay does not support
  directories) → disabled, reason "Folders not supported between two remote
  hosts".
- Otherwise enabled → calls the existing `_transfer(fromLeft: …,
  entries: [entry])` with the clicked entry (consistent with how Rename/Delete
  act on the clicked entry).

### 3. Refresh / New Folder

Reuse existing plumbing:

- Remote: `_loadDirectory(prov.currentPath)` and `_showNewFolderDialog`.
- Local: `prov.reload()` and the existing New Folder dialog.

### 4. Edit Permissions

- **Model:** add `int? mode` (permission bits) to `SftpEntry`; populate from
  `item.attr.mode` in `SftpTransferService.listDirectory`. Local entries read
  current mode via `FileStat`.
- **Service:** `SftpFileOpsService.chmod(host, path, mode, {recursive})` using
  `sftp.setStat(path, SftpFileAttrs(mode: …))`; the recursive walk follows the
  existing `_deleteRecursive` pattern. Local chmod uses
  `Process.run('chmod', …)` (macOS/Linux only; the menu item is hidden on
  Windows).
- **UI:** new `PermissionsDialog` widget — 9 checkboxes (owner/group/others ×
  read/write/execute) two-way synced with an octal text field (e.g. `755`),
  preloaded with the entry's current mode. Directories additionally get an
  "Apply recursively" checkbox. Apply → chmod → refresh the panel; errors
  surface via snackbar (same pattern as other ops).

### 5. Error handling

All new operations follow the panels' existing pattern: try/catch around the
service call, snackbar with the failure message, then refresh the listing.

### 6. Testing

- Unit tests for octal ↔ rwx-checkbox conversion logic.
- Unit test for `SftpFileOpsService.chmod` recursive walk (mocked SFTP).
- `flutter analyze` and `flutter test` must pass.

## Files touched

| File | Change |
| --- | --- |
| `app/lib/widgets/sftp_entry_context_menu.dart` | → `entry_context_menu.dart`, generalized + new items |
| `app/lib/widgets/sftp_panel.dart` | wire new callbacks, drop "Enter" label |
| `app/lib/widgets/local_file_panel.dart` | replace `showMenu` with shared widget, wire callbacks |
| `app/lib/widgets/dual_panel_sftp_screen.dart` | copy-to-target plumbing, permissions wiring |
| `app/lib/models/sftp_entry.dart` | add `mode` |
| `app/lib/services/sftp_transfer_service.dart` | populate `mode` in `listDirectory` |
| `app/lib/services/sftp_file_ops_service.dart` | add `chmod` (+ recursive) |
| `app/lib/widgets/permissions_dialog.dart` | new |

## Out of scope

- Multi-select context-menu actions (menu acts on the clicked entry, as today).
- Directory copy between two remote hosts (relay stays file-only).
- Showing permission strings in the entry rows (reference screenshots show
  them, but this design covers the context menu only).
