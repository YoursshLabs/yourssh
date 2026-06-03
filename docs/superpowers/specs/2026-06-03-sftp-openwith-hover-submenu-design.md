# SFTP "Open with" Hover Submenu — Design

**Date:** 2026-06-03

## Goal

The "Open with ▶" entry in the SFTP file context menu currently requires a click, which closes the parent menu and opens a second standalone menu. Replace this two-step flow with a native-feeling cascading submenu that opens on **hover** (and on click), keeping the parent menu visible.

## Approach

Migrate `SftpEntryContextMenu` from `showMenu`/`PopupMenuItem` to Flutter's Material 3 menu system — `MenuAnchor` + `MenuItemButton` + `SubmenuButton` (available since Flutter 3.7; the project is on 3.44). `SubmenuButton` opens its submenu on hover on desktop platforms out of the box.

## Changes

### `SftpEntryContextMenu` (rewrite)

- Becomes a `StatefulWidget` holding a `MenuController` and the loaded `List<AppOption>`.
- `GestureDetector.onSecondaryTapUp` → `_controller.open(position: d.localPosition)` (position is anchor-relative, which matches `localPosition`).
- Menu structure (files): **View**, **Edit**, **Open with ▶** (SubmenuButton), divider, **Rename**, **Delete**, divider, **Copy path**. Directories keep **Enter** + Rename/Delete/Copy path.
- Dark styling preserved via `MenuStyle` (background `0xFF1E1E1E`, border `0xFF2A2A2A`, radius 8) and compact `ButtonStyle` on items (13 px text, `0xFFD4D4D4`).

### New widget API

```dart
SftpEntryContextMenu({
  required SftpEntry entry,
  required Widget child,
  required VoidCallback onOpen,            // directory Enter
  VoidCallback? onView,                    // files
  VoidCallback? onEdit,                    // files
  Future<List<AppOption>> Function()? loadApps,   // fetch app list (cached per ext)
  void Function(AppOption app)? onOpenWithApp,    // app picked from list
  VoidCallback? onChooseApp,               // "Choose…" file picker
  required VoidCallback onRename,
  required VoidCallback onDelete,
})
```

The old `onOpenWith(Offset)` callback is removed — positioning is now handled inside the widget by the submenu itself.

### Async app loading

- On right-click, the menu opens immediately; `loadApps()` fires in parallel.
- While loading, the submenu shows a disabled "Searching apps…" item plus "Choose…".
- When the future completes, `setState` swaps in the app list (name + "default" chip). `AppDiscoveryService` already caches per extension, so subsequent opens are instant.

### `sftp_panel.dart`

- Delete `_showOpenWithSubmenu` and the `_OpenWithChoice` helper class (the second `showMenu` flow).
- Keep `_pickApp()` (file picker) and the launch/watch logic; expose them via the new callbacks:
  - `loadApps: () => discovery.getAppsFor(stubPath)` (stub path built from `entry.extension`)
  - `onOpenWithApp: (app) => _openWithApp(entry, app.executablePath)`
  - `onChooseApp: () async { final p = await _pickApp(); if (p != null) _openWithApp(entry, p); }`
- `_openWithApp(entry, appPath)` — extracted launch helper: wires snackbar callbacks, calls `ExternalEditService.openExternalWith`, shows success/error snackbars.

## Error handling

- `loadApps()` failure → submenu shows only "Choose…" (discovery already returns `[]` on error).
- Everything else unchanged (launch failures → snackbar).

## Testing

- Rewrite `sftp_entry_context_menu_test.dart` for the MenuAnchor structure:
  - Right-click shows View / Edit / Open with for files.
  - **Hover** over "Open with" (mouse gesture: `createGesture(kind: mouse)` → `moveTo`) opens the submenu listing app names without any click.
  - Tapping an app item calls `onOpenWithApp` with that `AppOption`.
  - Tapping "Choose…" calls `onChooseApp`.
  - Directory entries show Enter and no Open with.
- Full suite + analyzer clean.

## Out of scope

- App icons in the submenu (unchanged best-effort plumbing).
- Hover behavior on touch platforms (SubmenuButton falls back to tap — acceptable).
