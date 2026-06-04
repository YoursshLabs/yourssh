# SFTP: docked transfer panel + local-panel checkboxes

Date: 2026-06-04 · Status: approved

## Goal

Two UX gaps in the two-panel SFTP workspace:

1. The local panel has no checkboxes — selection is click/cmd-click only,
   while the remote panel offers per-row checkboxes and a select-all header.
2. Transfer progress is a centered modal dialog that blocks the workspace.
   It should dock at the bottom, be minimizable, and let transfers run in
   the background while the user keeps working.

## A. Local panel checkboxes (parity with the remote panel)

- Each `_LocalEntryRow` gains a leading `Checkbox` bound to
  `toggleSelection(entry)`. Row tap (select), cmd/ctrl-click (multi),
  double-tap (open dir) and right-click (context menu) keep their current
  behavior.
- A header bar above the list mirrors the remote panel: a tristate
  select-all `Checkbox` plus a `N items / N selected` label.
- `LocalFilePanelProvider` additions:
  - `isAllSelected` — true when every *visible* (filtered) entry is
    selected; select-all toggles between `selectAll()` (already
    filter-aware) and `deselectAll()`.
  - `setFilterQuery` prunes selected paths that the narrowed filter hides —
    parity with the equivalent SftpPanelProvider fix (bulk actions must
    never touch entries the user cannot see).

## B. Docked transfer panel (replaces the modal dialog)

New widget `SftpTransferPanel` rendered at the bottom of
`DualPanelSftpScreen`'s `Column` whenever `SftpTransferProvider.items` is
non-empty. Non-modal: the workspace stays interactive, and since transfers
already run in the provider (the old dialog was only a view), they continue
in the background regardless of panel state.

- **Expanded (default)**: header `Transferring x/y files` with minimize
  (`—`) and `Cancel`; overall progress bar; per-file list (max height
  ~200 px) with the same status rows as the old dialog.
- **Minimized**: a slim strip — progress bar, `x/y files`, expand (`˄`),
  `Cancel`.
- **Completion**: shows the done state, then auto-clears after ~3 s —
  unless any item errored, in which case the panel stays until the user
  closes it (`✕`).
- The top-of-screen `LinearProgressIndicator` is removed (redundant).
- `SftpTransferDialog` and the `showDialog` flow are deleted.

### Provider changes (`SftpTransferProvider`)

- `startBatch` **appends** to the running list when a batch is already
  active (`isTransferring`), otherwise replaces it. Multiple transfer loops
  run concurrently; `updateItem` is id-keyed so they don't interfere.
- `cancel()` cancels **everything** (single flag, documented) and marks
  every item that is not done/error as `skipped`, so `isTransferring`
  cannot stay latched on a cancelled batch.

## C. Tests

- Provider: local `isAllSelected` + filter pruning; transfer `startBatch`
  append semantics; `cancel` marks unfinished items skipped.
- Widget: local panel renders per-row checkboxes and a working select-all
  header; transfer panel appears on batch start, minimizes to the strip,
  auto-hides ~3 s after success, stays visible on error, Cancel wires to
  the provider.

## Out of scope

- Per-batch cancel (Cancel stops all running transfers).
- Transfer reordering/pause-resume.
- Concurrent-batch bandwidth management — loops already interleave today.
