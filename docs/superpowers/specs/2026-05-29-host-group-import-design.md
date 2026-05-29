# Host Group Management & Import — Design Spec

**Date:** 2026-05-29  
**Scope:** New Group panel + Import panel (right-side panel pattern, no modals)

---

## Overview

Two features added to the Hosts screen:

1. **New Group** — create a named group (possibly empty) via a right-side panel
2. **Import Hosts** — import hosts from `.ssh/config` or JSON via a right-side panel

Both panels follow the existing `HostDetailPanel` pattern: 340px wide, slides in as a `Row` child on the right of `MainScreen`, same visual style.

---

## 1. Panel System (`MainScreen`)

Replace the current `bool _showHostPanel` with an enum:

```dart
enum _SidePanel { none, host, newGroup, import }
_SidePanel _sidePanel = _SidePanel.none;
Host? _editingHost;
String? _initialGroup;
```

`_buildContent` renders the appropriate panel as the last child of the `Row` based on `_sidePanel`. All panels use `onClose` → `setState(() => _sidePanel = _SidePanel.none)`.

No other logic changes in `MainScreen`.

---

## 2. New Group Panel (`NewGroupPanel`)

**File:** `app/lib/widgets/new_group_panel.dart`

### UI

- Header: "New Group" title + close button (same style as `HostDetailPanel._buildHeader`)
- Body:
  - Single `_Card` with one field: group name (icon: `Icons.folder_outlined`, autofocus)
  - Validation: non-empty, not duplicate of existing group names
- Footer: full-width "Save" button (same style as `HostDetailPanel` Save button)

### Behavior

- On save: calls `HostProvider.addGroup(name)`, closes panel
- Group name is stored trimmed, case-preserved
- If group already exists: show inline validation error, do not save
- `_GroupCard` in `HostsDashboard` gains a hover context menu (same `...` button pattern as host cards) with a single "Delete group" action → calls `HostProvider.removeGroup(name)`. This removes it from `pinnedGroups`; if the group still has hosts, those hosts keep their `group` field but the card rebuilds from the host list as before.

### Storage (`HostProvider` + `StorageService`)

`HostProvider` gains:

```dart
List<String> _pinnedGroups = [];
List<String> get pinnedGroups => List.unmodifiable(_pinnedGroups);

Future<void> addGroup(String name) async { ... }
Future<void> removeGroup(String name) async { ... }
```

`StorageService` gains:

```dart
static const _groupsKey = 'pinned_groups';
Future<List<String>> loadPinnedGroups() async { ... }
Future<void> savePinnedGroups(List<String> groups) async { ... }
```

`HostsDashboard` derives groups by merging `pinnedGroups` (from provider) with the set of group names already on hosts. Empty pinned groups still show as cards.

---

## 3. Import Panel (`ImportPanel`)

**File:** `app/lib/widgets/import_panel.dart`

### UI Sections

**Header**: "Import Hosts" + close button

**Input toggle** (segmented control at top of body):
- `From file` — shows a "Choose file" button; pressing opens `FilePicker.platform.pickFiles()`; on success, reads file content and auto-parses
- `Paste text` — shows a `TextField` (multiline, monospace, ~10 lines) + "Parse" button

**Format detection** (applied to the raw string):
- Starts with `Host ` (case-insensitive) → treat as `.ssh/config`
- Otherwise → attempt JSON parse (`List<Map>` or single `Map`)
- If neither parses → show error banner "Unrecognized format"

**Preview list**: rendered after a successful parse, before confirming import
- Each row: hostname, label, username, port
- Checkbox per row (default checked) to include/exclude
- Duplicate detection: compare `host + username` against existing hosts
  - If duplicate found: row shows an amber "Duplicate" badge + a `Skip / Overwrite` toggle (default: Skip)

**Footer**: "Import N hosts" filled button (N = checked non-skipped rows); disabled when N = 0

### Parsers

**`.ssh/config` parser** (internal utility, not a separate file):
- Split on `^Host ` blocks
- Extract `HostName`, `User`, `Port` fields
- `Host <alias>` line → `label`
- Missing `User` → default `root`; missing `Port` → default `22`
- Skip `Host *` wildcard blocks

**JSON parser**:
- Accepts array of objects matching the existing export format (`label`, `host`, `port`, `username`, `authType`, `group`, `tags`)
- Maps directly to `Host.fromJson`; generates new `id` for each (never re-use imported IDs to avoid silent overwrites)

### Import execution

```
for each checked row:
  if duplicate && toggle == Overwrite:
    hostProvider.updateHost(existing.copyWith(...imported fields...))
  else if not duplicate:
    hostProvider.addHost(newHost)
  // Skip: do nothing
close panel
show SnackBar: "Imported X hosts"
```

Passwords are not importable (not stored in export format). After import, user sets passwords individually.

---

## 4. Button Placement (`_TopBar` in `HostsDashboard`)

Replace the existing `_OutlinedBtn(label: 'NEW HOST', ...)` with a **split button**:

```
┌──────────────┬───┐
│  + NEW HOST  │ ˅ │
└──────────────┴───┘
```

- Left half: same behavior as current NEW HOST button (opens host panel)
- Right chevron: `PopupMenuButton` showing two items:
  - "New Group" (icon: `Icons.create_new_folder_outlined`) → calls `onNewGroup()`
  - "Import" (icon: `Icons.upload_file_outlined`) → calls `onImport()`

`HostsDashboard` gains two new callbacks:
```dart
final VoidCallback? onNewGroup;
final VoidCallback? onImport;
```

`MainScreen` wires these to `setState(() => _sidePanel = _SidePanel.newGroup)` and `setState(() => _sidePanel = _SidePanel.import)`.

---

## 5. Files Changed / Created

| File | Change |
|------|--------|
| `app/lib/screens/main_screen.dart` | Replace `_showHostPanel` bool with `_SidePanel` enum; wire `onNewGroup` + `onImport` callbacks |
| `app/lib/providers/host_provider.dart` | Add `pinnedGroups`, `addGroup`, `removeGroup` |
| `app/lib/services/storage_service.dart` | Add `loadPinnedGroups`, `savePinnedGroups` |
| `app/lib/widgets/hosts_dashboard.dart` | Split button, `onNewGroup` + `onImport` callbacks, merge pinnedGroups into group cards |
| `app/lib/widgets/new_group_panel.dart` | **New file** |
| `app/lib/widgets/import_panel.dart` | **New file** |

---

## 6. Out of Scope

- Cloud integrations (AWS, DigitalOcean, Azure)
- Importing passwords (security boundary)
- Drag-and-drop group reordering
- Renaming or deleting groups from a dedicated UI (existing "Move to Group" covers group assignment)
