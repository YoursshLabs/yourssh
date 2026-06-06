# Dashboard Grid/List View Toggle + Host Sorting — Design

**Date:** 2026-06-06
**Status:** Approved

## Goal

Let the user switch the hosts dashboard between the existing card grid and a new
compact single-line list view, and sort hosts by name, creation date, or
hostname. Both choices persist across restarts.

## Background

`HostsDashboard` (`app/lib/widgets/hosts_dashboard.dart`) renders all filtered
hosts as a flat collection in `_HostGrid` (a responsive `Wrap`, 1–4 columns,
280 dp min card width). The "Groups" section above it is a row of `_GroupCard`
count tiles only — hosts are **not** visually partitioned by group, so sorting
applies to the single flat `filtered` list. Hosts currently render in insertion
order. No view-mode or sort preference exists today.

## UI

### Toolbar (`_TopBar`)

Two new controls between the host count and the SELECT button, styled to match
the existing 28×34 `_OutlinedBtn` look:

- **Sort dropdown** — `Icons.sort` plus the current mode's short label. Opens a
  menu with six entries:
  | Mode | Key |
  |---|---|
  | Name A→Z (default) | `name_asc` |
  | Name Z→A | `name_desc` |
  | Newest first | `created_desc` |
  | Oldest first | `created_asc` |
  | Host A→Z | `host_asc` |
  | Host Z→A | `host_desc` |
- **View toggle** — segmented pair of icon buttons (`Icons.grid_view`,
  `Icons.view_list`); the active side is highlighted.

The toolbar is replaced by `BulkActionBar` in selection mode, as today; the
sort and view mode still apply to the rendered hosts while selecting.

### List view row (`_HostListRow`)

Single-line, full-width row (one per host, 12 px vertical rhythm to match
cards):

```
│ ● 🐧 prod-web-01  ubuntu@10.0.1.5   ✓ 42ms   [test][sftp][⋮] │
```

- Leading: selection checkbox in selection mode, otherwise status dot;
  then a small OS icon (reuses `osIconAsset`).
- Label (primary text) followed by `user@host` in secondary color (port
  appended as `:port` only when ≠ 22), both ellipsized.
- Test-connection result inline on the right: `✓ <latency>ms` in green or
  `✗ <short error>` in red, single line, ellipsized. No row height change.
- Trailing hover actions: Test Connection, SFTP, more-menu — identical
  callbacks and context-menu items as `_HostCard` (edit, delete, etc.).
- Click behavior identical to the card (connect; toggle selection in
  selection mode).

### Grid view

Unchanged — existing `_HostCard` inside the `Wrap`.

## State & persistence

Both preferences live in `SettingsProvider` following its existing
`_load()` / `save()` pattern, stored in `SharedPreferences`:

- `dashboardViewMode` — `'grid'` (default) | `'list'`; key `dashboardViewMode`.
- `dashboardSort` — one of the six mode keys above; default `name_asc`; key
  `dashboardSort`. An unrecognized stored value falls back to the default.

Settings load before the first frame, so there is no wrong-view flash.
`HostsDashboard` reads both via `context.select` and writes via
`SettingsProvider.save(...)`.

Note: `name_asc` as the default changes the out-of-the-box ordering from
insertion order to alphabetical. This is intentional — the sort control always
reflects a real, predictable ordering.

## Sorting

A pure function in a new `app/lib/util/host_sort.dart` (no Flutter imports, so
unit tests stay lightweight):

```dart
List<Host> sortHosts(List<Host> hosts, HostSortMode mode)
```

- `HostSortMode` — enum with the six modes plus `fromKey(String?)` /
  `key` mapping for persistence.
- Name and host comparisons are case-insensitive.
- Tie-break: label (case-insensitive), then id, so ordering is stable and
  deterministic.
- Returns a new list; never mutates provider state.
- Applied to `filtered` in `HostsDashboard.build` before handing the list to
  the grid/list widget. Group tiles are unaffected.

## Rendering flow

```
filtered = query.isEmpty ? hosts : hosts.where(query.matches)
sorted   = sortHosts(filtered, settings.dashboardSort)
viewMode == grid ? _HostGrid(sorted, ...) : _HostList(sorted, ...)
```

`_HostList` is a simple `Column` of `_HostListRow`s (the dashboard already
scrolls via its outer `SingleChildScrollView`). Switching views or sort modes
must not touch `_selectedHostIds` or selection mode.

## Error handling

- Unknown persisted sort/view values → defaults (`name_asc`, `grid`).
- Hosts with identical labels/hosts sort deterministically via tie-breaks.

## Testing

- **Unit (`sortHosts`)**: each mode; case-insensitivity; createdAt ordering;
  tie-break stability; input list not mutated.
- **Widget (`HostsDashboard`)**:
  - toggle switches between card grid and list rows;
  - sort mode changes rendered order;
  - selection survives a view switch and a sort change;
  - list row shows inline test result and selection checkbox in selection mode;
  - preferences round-trip through `SettingsProvider`.
