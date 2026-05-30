# SFTP File Edit — Design Spec

**Date:** 2026-05-30  
**Status:** Approved

## Summary

Two additions to the SFTP feature:
1. **"Edit" in context menu** — explicit "Edit" menu item for files in the right-click context menu
2. **Create new file** — "New file" toolbar button that creates an empty file on the server and opens it in the editor
3. **Unsaved changes warning** — prevent accidental data loss when closing the editor with unsaved content

---

## Architecture

All changes stay within existing components. No new files needed except adding one method to `SftpFileOpsService`.

**Files touched:**
- `app/lib/widgets/sftp_entry_context_menu.dart` — add `onEdit` callback + menu item
- `app/lib/widgets/sftp_panel.dart` — wire `onEdit`, add New File button + dialog
- `app/lib/services/sftp_file_ops_service.dart` — add `createFile` method
- `app/lib/widgets/code_editor_screen.dart` — dirty tracking + unsaved changes dialog
- `assets/monaco_editor.html` — emit `change` event to Flutter

---

## Component Details

### 1. SftpEntryContextMenu

Add optional `VoidCallback? onEdit` parameter. Show "Edit" menu item (icon: `Icons.edit_outlined`) only when `!entry.isDirectory`, positioned after "Open". When `onEdit` is null, the item is not rendered.

```
[Enter / Open]
[Edit]          ← new, files only
─────────────
[Rename]
[Delete]
─────────────
[Copy path]
```

### 2. SftpPanel — "Edit" wiring

`_buildEntryTile` passes `onEdit: entry.isDirectory ? null : () => _onEntryTap(entry)`.

### 3. SftpPanel — New File button

Add `Icons.note_add_outlined` button (tooltip: "New file") in `_buildPathBar`, left of the "New folder" button.

`_showNewFileDialog` flow:
1. Show dialog to enter filename (same style as `_showNewFolderDialog`)
2. Build `remotePath = currentPath == '/' ? '/$name' : '$currentPath/$name'`
3. Call `SftpFileOpsService.createFile(host, remotePath)` — creates empty file
4. Build a temporary `SftpEntry` (size 0, `isDirectory: false`) for the new file
5. `Navigator.push(CodeEditorScreen(...)).then((_) => _loadDirectory(currentPath))` — refresh on return

### 4. SftpFileOpsService — createFile

```dart
Future<void> createFile(Host host, String remotePath) async {
  final sftp = await _sshService.openSftp(host);
  final file = await sftp.open(
    remotePath,
    mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
  );
  await file.close();
  sftp.close();
}
```

### 5. CodeEditorScreen — Dirty tracking

- Add `bool _isDirty = false`
- Monaco HTML emits `{type: 'change'}` via `FlutterChannel` on `onDidChangeModelContent`
- `_onJsMessage` sets `_isDirty = true` on `type == 'change'`
- `_saveFile` sets `_isDirty = false` on success
- Wrap `Scaffold` with `PopScope(canPop: !_isDirty, onPopInvokedWithResult: _onPopInvoked)`
- `_onPopInvoked` shows confirm dialog: "Discard changes?" with Cancel / Discard actions; if Discard → `Navigator.pop(context)`

### 6. monaco_editor.html

Add after editor initialization:
```js
editor.onDidChangeModelContent(function() {
  FlutterChannel.postMessage(JSON.stringify({ type: 'change' }));
});
```

---

## Data Flow

```
User right-clicks file
  → SftpEntryContextMenu shows "Edit"
  → onEdit() → _onEntryTap(entry) → Navigator.push(CodeEditorScreen)

User clicks "New file" button
  → _showNewFileDialog()
  → SftpFileOpsService.createFile(host, path)
  → Navigator.push(CodeEditorScreen with empty SftpEntry)
  → .then(_) => _loadDirectory(currentPath)

User edits in Monaco
  → JS: onDidChangeModelContent → FlutterChannel {type:'change'}
  → Dart: _isDirty = true

User clicks Save / Ctrl+S
  → _saveFile() → uploadFile() → _isDirty = false

User clicks back with _isDirty == true
  → PopScope blocks pop
  → Dialog: "Discard changes?"
  → Cancel: stay / Discard: Navigator.pop()
```

---

## Error Handling

- `createFile` fails → SnackBar "Create file failed: $e" (same pattern as `_showNewFolderDialog`)
- `downloadToTemp` returns null for new empty file → `CodeEditorScreen` handles null gracefully (already does: `if (tmpPath == null || !mounted) return`)
- `_saveFile` failure → existing SnackBar error already handled

---

## Out of Scope

- Binary file detection (opening images/executables in editor)
- File size limit warning
- Multiple editor tabs
