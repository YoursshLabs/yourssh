# SFTP Editor Fallback + External Edit — Design

**Date:** 2026-06-03
**Issue:** [#34](https://github.com/YoursshLabs/yourssh/issues/34) — opening a file from the SFTP panel on Linux blanks the whole window.

## Problem

`CodeEditorScreen` unconditionally constructs a `WebViewController` in `initState` to host the Monaco editor. `webview_flutter` only ships platform implementations for Android (`webview_flutter_android`) and iOS/macOS (`webview_flutter_wkwebview`). On Linux and Windows `WebViewPlatform.instance` is `null`, so the controller constructor throws, the route fails to build, and the app renders a full-window gray error box.

Separately, the editor is useless for binary or very large files on every platform, and there is no way to hand a file off to an external application.

## Goals

1. Opening a file from SFTP on Linux/Windows must never crash; text files remain editable in-app.
2. Files the app cannot edit (binary, too large) offer "open with external app" instead.
3. External edits round-trip: changes saved by the external app are uploaded back to the server automatically.
4. Any file can be opened externally on demand via the SFTP context menu.

## Design

### 1. Webview fallback editor (fixes #34)

`CodeEditorScreen.initState` checks `WebViewPlatform.instance != null`:

- **Available** (macOS, mobile): current Monaco/webview path, unchanged.
- **Unavailable** (Linux, Windows): skip `WebViewController` creation entirely. Render a plain-Flutter editor: full-screen multiline `TextField`, monospace font, existing dark palette. Dirty tracking via `onChanged`; save via the existing AppBar button and `Ctrl+S` (`CallbackShortcuts`). Load/save reuse the existing `SftpTransferService` logic (`downloadToTemp` / `uploadFile`).

### 2. Unsupported-file detection

New pure helper `app/lib/services/sftp_file_inspector.dart`:

- `isBinaryExtension(name)` — known binary extensions (images, archives, executables, media, pdf, …). Checked **before** download.
- `isTooLarge(size)` — threshold 5 MB. Checked **before** download (size comes from the directory listing).
- `looksBinary(bytes)` — null byte within the first 8 KB. Checked **after** download, before handing content to the editor.

When any check trips, show a dialog: *"Cannot edit this file in-app — open with external app?"* → [Open externally / Cancel].

### 3. External edit service (watch + auto-upload)

New `ExternalEditService` (`app/lib/services/external_edit_service.dart`):

- `openExternal(host, entry)`:
  1. Download to `{tmp}/yourssh_edit/{sessionId}/{filename}` (per-session directory avoids name collisions with the transfer temp dir).
  2. Launch the OS default application via `launchUrl(Uri.file(path))` (`url_launcher`, already a dependency, supports macOS/Windows/Linux).
  3. Start watching the local file by **polling mtime every 2 s** (robust against editors that save via rename-over, which breaks inotify/FSEvents watches; same strategy as WinSCP).
- On mtime change → `SftpTransferService.uploadFile` back to `entry.path` → success snackbar ("Uploaded <name> to server").
- Upload failure → red snackbar; watcher keeps running so the next save retries.
- Watchers live until app exit; `dispose()` cancels all polling timers.

### 4. Entry points (SFTP panel)

- `SftpEntryContextMenu`: new item **"Open with external app"** for every file (also available for editable text files).
- Double-click (`_onEntryTap`): run pre-download checks (extension, size). Unsupported → external-open dialog; otherwise → `CodeEditorScreen` as today.

## Error handling

- `WebViewPlatform.instance == null` is a supported state, not an error.
- Download/launch/upload failures surface as snackbars; nothing crashes the route.
- The post-download null-byte check closes the editor and offers external open instead.

## Testing

- **Widget test (reproduces #34):** pump `CodeEditorScreen` in the test environment (no `WebViewPlatform.instance`, same as Linux) with a fake `SftpTransferService`; expect the fallback editor instead of a crash. Cover content load, dirty tracking, and save → `uploadFile`.
- **Unit tests:** `sftp_file_inspector` (extension list, size threshold, null-byte sniffing); `ExternalEditService` poll→upload loop using a fake transfer service and real temp files.

## Out of scope

- Bundling a Linux/Windows webview implementation for Monaco.
- Conflict detection when the remote file changes while an external edit session is active (last write wins).
- Persisting watch sessions across app restarts.
