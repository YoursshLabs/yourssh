# S3 Browser Enhancements — Design Spec

**Date:** 2026-05-29  
**Status:** Approved

## Overview

Extend the existing `S3BrowserScreen` / `S3Service` with five missing features: multiple bucket configs, direct download, create folder, rename/move, and upload progress. Pattern stays consistent with other DevOpsHub screens (self-contained `StatefulWidget`, no separate provider).

---

## 1. Multiple Bucket Configs

### Model

New `S3BucketConfig` class in `app/lib/models/s3_bucket_config.dart`:

```dart
class S3BucketConfig {
  final String id;       // uuid v4
  final String name;     // display label
  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;
}
```

Serialized to/from JSON. `id` is a UUID used as the storage key.

### Persistence

- Single secure storage key `s3_configs` holds a JSON array of `S3BucketConfig` objects (without `secretKey`).
- Secret keys stored separately per-config: `s3_secret_<id>`.
- On load: read array, read each secret separately, reconstruct full list.

### UI

- Toolbar dropdown replaces the static bucket name label.
- Dropdown shows config `name` values; selecting one switches the active bucket (resets prefix, reloads).
- "+" icon button beside the dropdown opens the existing config form as an "Add bucket" sheet.
- Hovering a dropdown item reveals trailing Edit / Delete icon buttons.
- Deleting the active config switches to the first remaining config, or back to unconfigured state if none left.

### Migration

Existing single-config keys (`s3_endpoint`, `s3_bucket`, etc.) are migrated on first load: if found, create a `S3BucketConfig` with name = bucket value, save it, delete old keys.

---

## 2. Direct Download

### Service

`S3Service.downloadObject(String key) → Future<Uint8List>` — signed GET, returns response bytes. Reuses `_signedGet`.

### UI

- "Download" action button added to `_EntryTile` hover row (beside Copy URL / Open / Delete).
- On tap: call `downloadObject`, then write bytes to `~/Downloads/<filename>` using `dart:io`.
- Show SnackBar: "Saved to Downloads/filename" on success, error message on failure.
- No file picker — always saves to system Downloads folder (`Platform.isWindows` → `%USERPROFILE%\Downloads`, macOS → `~/Downloads`).

---

## 3. Create Folder

### Service

No new service method needed. Create folder = `putObject('${prefix}${name}/', Uint8List(0))`.

### UI

- "New Folder" icon button added to toolbar (only shown when `_configured`).
- Tap opens a simple `AlertDialog` with a single `TextField` for folder name.
- Validates: non-empty, no `/` characters.
- On confirm: calls `putObject` with trailing slash key, then reloads list.

---

## 4. Rename / Move

### Service

`S3Service.copyObject(String sourceKey, String destKey) → Future<void>`  
PUT request to `destKey` URL with header `x-amz-copy-source: /<bucket>/<encodedSourceKey>` and `x-amz-metadata-directive: COPY`. Body is empty. After successful copy, `deleteObject(sourceKey)`.

### UI

Single "Rename / Move" dialog with two fields:
- **Folder** (pre-filled with current prefix, e.g. `images/2024/`)
- **Filename** (pre-filled with current `entry.name`)

User edits either or both. On confirm: construct `destKey = folder + filename`, call `copyObject(entry.key, destKey)`, then `deleteObject(entry.key)`, then reload.

Action button in `_EntryTile` hover row: pencil icon, shown only for files (not prefixes).

---

## 5. Upload Progress

### Service

`S3Service.putObject` gains an optional `void Function(int sent, int total)? onProgress` parameter.

Implementation: replace `http.put(...)` with `http.StreamedRequest('PUT', uri)`. Feed `data` to `request.sink` in chunks (e.g. 64 KB), calling `onProgress` after each chunk. Await `http.Response.fromStream(...)`.

### UI

- `_S3BrowserScreenState` adds `double? _uploadProgress` (null = not uploading, 0.0–1.0 = in progress).
- `_upload()` passes `onProgress` callback that calls `setState(() => _uploadProgress = sent/total)`.
- A `LinearProgressIndicator` appears at the bottom of the screen (above the file list) when `_uploadProgress != null`.
- After upload completes or errors: `_uploadProgress = null`.

---

## File Changes Summary

| File | Change |
|------|--------|
| `app/lib/models/s3_bucket_config.dart` | **New** — config model |
| `app/lib/services/s3_service.dart` | Add `downloadObject`, `copyObject`; update `putObject` with progress |
| `app/lib/widgets/s3_browser_screen.dart` | Multiple buckets UI, download/create folder/rename-move actions, progress bar |
| `app/pubspec.yaml` | No new deps needed (`dart:io`, `http` already present) |

---

## Error Handling

- All service calls wrapped in try/catch; errors shown in `_error` state (existing pattern).
- Copy+delete is not atomic: if delete fails after copy succeeds, log the error but don't surface as "rename failed" (the copy succeeded; user can manually delete the old key).
- Folder creation with existing name: S3 silently overwrites the empty marker — acceptable.

## Out of Scope

- Multi-file upload / batch operations
- Upload to a specific subfolder via drag-and-drop
- Object versioning / restore
- ACL / permissions management
