# SFTP Two-Panel Redesign — Design

Date: 2026-06-04
Status: approved

## Problem

The SFTP screen is a fixed three-panel layout: Local | Remote A | Remote B.
The local panel is pinned to the local filesystem and the two remote slots
cannot show local files. Users want a classic two-panel commander layout
where each side can point at any source.

## Requirements

- Exactly two panels: left and right.
- Each panel can switch between the **Local filesystem** and **any saved
  SSH host** at any time.
- Left panel defaults to Local; right panel starts unconnected
  ("Connect" prompt).
- All source combinations are allowed, including both panels on the same
  source. Copy works for every combination.

## Design (slot-based composition)

### Model: `PanelSource`

`app/lib/models/panel_source.dart` — a sealed-style type with two cases:
`LocalSource` and `HostSource(Host)`. Equality by case + host id.

### Slots

`_DualPanelSftpScreenState` replaces `_hostA`/`_hostB` with `_sourceLeft`
(default `LocalSource`) and `_sourceRight` (default `null` → "Connect"
prompt). Each slot owns one `LocalFilePanelProvider` **and** one
`SftpPanelProvider`, so switching a slot's source back and forth preserves
both paths. Slot renders the existing `LocalFilePanel` or `SftpPanel`
depending on the source. All slot state survives tab switches via the
existing `KeepAliveOffstage` layer (issue #42).

### Source picker

The existing host picker dialog becomes a source picker: a pinned
**Local** entry (laptop icon) on top, then the saved hosts list. Both
panels open it from the source chip in their top bar: `SftpPanel` reuses
its existing `user@host` chip (`onChangeHost` → now "change source");
`LocalFilePanel` gains an equivalent "Local" chip next to its breadcrumb
(new optional `onChangeSource` parameter; chip hidden when not provided,
so other usages are unaffected).

### Transfer matrix

A pure function decides the mechanism; the buttons and drag & drop both
dispatch through it:

| From → To       | Mechanism                                            |
|-----------------|------------------------------------------------------|
| Local → Local   | filesystem copy (files + recursive directories) — new |
| Local → Remote  | existing upload path                                 |
| Remote → Local  | existing download path                               |
| Remote → Remote | existing temp-file relay (files only, dirs skipped)  |

`transferKindFor(src, dst)` returns an enum
(`localCopy | upload | download | remoteRelay`). Same-host remote→remote
still goes through the temp relay (server-side `cp` is out of scope).
Progress reporting keeps using `SftpTransferProvider` for all kinds.

### Connection notifier

`_sftpConnectionNotifier` (hides the sidebar for full-width layout) is
`true` whenever at least one panel has a `HostSource`.

### Drag & drop

Each slot accepts drops of both `LocalEntry` and `SftpEntry`; a drop
triggers the same matrix dispatch as the copy buttons.

## Panel header refinements (approved follow-up)

Both panels share the same header structure: `[source chip] … [Filter] [Actions ▾]`.

- Local panel: the static "Local" header title becomes the clickable source
  chip (laptop icon + "Local"); the chip is removed from the breadcrumb row.
- Remote panel: gains the same header. Its chip shows the **host label**
  (ellipsized) instead of `user@host`, plus the `root` badge when elevated.
- Remote panel gains the local panel's filter feature: `SftpPanelProvider`
  adds `filterVisible` / `toggleFilterVisible` / `filterQuery` /
  `setFilterQuery` / `filteredEntries`; the list renders `filteredEntries`.
- Remote actions (New File, New Folder, Rename, Delete) move from inline
  toolbar buttons into the header's Actions menu. The breadcrumb row keeps
  Up + breadcrumb + Refresh.

## Out of scope

- Server-side copy for same-host transfers.
- Directory copy for remote→remote.
- Back/forward history for the remote panel.

## Testing

- Unit: `transferKindFor` covers all four combinations.
- Unit: local recursive copy helper (temp directories, nested files).
- Unit: `PanelSource` equality.
- Widget: source picker shows Local entry plus hosts; selecting Local
  renders the local panel in that slot.
