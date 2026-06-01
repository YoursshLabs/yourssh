# Advanced Tab Management — Design Spec

**Date:** 2026-06-01
**Status:** Approved

## Overview

Add four tab management features to the session tab bar: rename, color tag, pin, and drag reorder. All metadata persists per host across reconnects via `SharedPreferences`.

## Scope

| Feature | Description |
|---|---|
| Rename | Double-click or right-click → Rename. Inline `TextField` on tab. Custom label overrides `user@host`. |
| Color tag | 8 preset colors shown as a dot on the tab. Right-click → Color tag submenu. |
| Pin | Pinned tabs stay at the left of the tab bar and cannot be accidentally closed. |
| Drag reorder | Drag tabs left/right to reorder. Pinned and unpinned zones are separate — a tab cannot be dragged across the boundary. |

Out of scope for this sprint: tab groups, duplicate-to-new-tab.

## Architecture

### Approach chosen: Extend `SshSession` + `TabMetadataService`

Runtime metadata lives directly on `SshSession`. A thin `TabMetadataService` persists metadata to `SharedPreferences` keyed by `hostId`. No new provider needed.

## Section 1 — Data Model

### `SshSession` — new fields

```dart
String? customLabel   // null = use default "user@host"
String? colorTag      // null | CSS hex e.g. "#ef4444"
bool isPinned         // default false
```

`SshSession.title` getter updated:

```dart
String get title => customLabel ?? (isWatch ? '[WATCH] ${watchedTitle ?? host.host}' : '${host.username}@${host.host}');
```

### `TabMetadataService` — new file

**Path:** `app/lib/services/tab_metadata_service.dart`

```dart
// SharedPreferences key: "tab_meta_<hostId>"
// Stored as JSON: {"label": "...", "color": "#ef4444", "pinned": true}

Future<void> saveMetadata(String hostId, {String? label, String? color, bool? pinned})
Future<Map<String, dynamic>?> loadMetadata(String hostId)
Future<void> clearMetadata(String hostId)
```

`SessionProvider.connect()` calls `loadMetadata(host.id)` after creating the session and applies any stored values.

## Section 2 — SessionProvider Changes

Four new methods added to `SessionProvider`:

```dart
void renameSession(String sessionId, String? label)
// Sets session.customLabel, saves via TabMetadataService, notifyListeners.

void setSessionColor(String sessionId, String? colorHex)
// Sets session.colorTag, saves via TabMetadataService, notifyListeners.

void togglePin(String sessionId)
// Toggles session.isPinned, saves, then calls _sortSessions() to move
// pinned tabs to the front of _sessions. notifyListeners.

void reorderSession(int oldIndex, int newIndex)
// Standard list reorder. Enforces pinned boundary: unpinned tabs cannot
// be dragged into the pinned zone and vice versa.
// After reorder, calls WorkspaceService.save() to persist new order.
```

**Pin sort rule:** `_sortSessions()` does a stable partition — pinned tabs to front, unpinned tabs after. Order within each group is preserved.

**Drag boundary:** `reorderSession` clamps `newIndex` to the pinned/unpinned boundary before applying the move.

## Section 3 — UI Changes

### `_SessionTab` widget updates

- **Color dot:** 7px circle rendered left of the label when `session.colorTag != null`.
- **Pin icon:** `Icons.push_pin` size 11 rendered right of label when `session.isPinned`.
- **Close button:** Hidden (not rendered) when `session.isPinned`. User must unpin first via context menu.
- **Double-tap / `onDoubleTap`:** Activates inline rename mode — label replaced with a focused `TextField`. `onSubmitted` / Escape to commit/cancel.
- **Right-click / `onSecondaryTap`:** Shows context menu via `showMenu`.

### Context menu

```
✏️  Rename
📌  Pin  /  Unpin
🎨  Color tag  ›   (submenu)
─────────────────
✕   Close
```

### Color submenu

8 color dots in a single row + a "None" option to clear:

| Name | Hex |
|---|---|
| Red | `#ef4444` |
| Orange | `#f97316` |
| Yellow | `#eab308` |
| Green | `#22c55e` |
| Teal | `#14b8a6` |
| Blue | `#3b82f6` |
| Purple | `#a855f7` |
| Pink | `#ec4899` |

### Drag reorder

`ListView` in `_TopTabBar` replaced with `ReorderableListView` (Flutter built-in). `onReorder` callback → `provider.reorderSession(oldIndex, newIndex)`. A visual drop indicator (standard Flutter `ReorderableListView` handle) shows the drop target while dragging.

## Persistence Flow

```
connect(host)
  └── TabMetadataService.loadMetadata(host.id)
        └── apply customLabel / colorTag / isPinned to new SshSession

renameSession / setSessionColor / togglePin
  └── update SshSession field
  └── TabMetadataService.saveMetadata(host.id, ...)
  └── notifyListeners

reorderSession
  └── reorder _sessions list (respects pinned boundary)
  └── WorkspaceService.save()  ← persists tab order
  └── notifyListeners
```

## Files Affected

| File | Change |
|---|---|
| `app/lib/models/ssh_session.dart` | Add `customLabel`, `colorTag`, `isPinned` fields; update `title` getter |
| `app/lib/services/tab_metadata_service.dart` | **New file** — load/save/clear per-host metadata |
| `app/lib/providers/session_provider.dart` | Add `renameSession`, `setSessionColor`, `togglePin`, `reorderSession`; call `loadMetadata` in `connect` |
| `app/lib/screens/main_screen.dart` | Update `_SessionTab` (dot, pin icon, double-tap, right-click menu, color submenu); replace `ListView` with `ReorderableListView` in `_TopTabBar` |

## Testing Notes

- Rename persists after closing and reopening session to same host
- Color dot appears on tab and persists across reconnect
- Pinned tab's close button is hidden; user must unpin via context menu before closing
- Drag reorder blocked at pinned/unpinned boundary
- Workspace snapshot preserves new tab order after app restart
