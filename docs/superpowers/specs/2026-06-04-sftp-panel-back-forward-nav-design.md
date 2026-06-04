# SFTP Panel Back/Forward Navigation — Design

**Date:** 2026-06-04
**Status:** Approved

## Problem

In the dual-panel SFTP view, the left (local) panel has back/forward navigation
chevrons backed by a history stack in `LocalFilePanelProvider`. The right
(remote SFTP) panel only has an Up button and breadcrumb — no history, no
back/forward buttons. The right panel should have the same control with the
same behavior.

## Changes

### 1. `SftpPanelProvider` (`app/lib/providers/sftp_panel_provider.dart`)

Add a history stack mirroring `LocalFilePanelProvider`:

- `_history` (List<String>) and `_historyIndex` (int) fields
- Getters: `canGoBack` (`_historyIndex > 0`), `canGoForward`
  (`_historyIndex < _history.length - 1`)
- `setPath(path)` pushes onto the history:
  - If the new path equals the current history entry, skip the push
    (prevents the Refresh button from polluting history)
  - If the index is mid-history (after goBack), truncate the forward
    entries before appending
  - Selection is cleared, listeners notified (existing behavior kept)
- `goBack()` / `goForward()` move the index and update `_currentPath`
  without pushing; clear selection, notify listeners

### 2. `SftpPanel` widget (`app/lib/widgets/sftp_panel.dart`)

- Split `_loadDirectory(path)` into:
  - `_fetchEntries(path)` — load state + SFTP list + `setEntries`,
    never touches history
  - `_loadDirectory(path)` — `prov.setPath(path)` (records history)
    then `_fetchEntries(path)`
- Back/forward handlers: call `prov.goBack()` / `prov.goForward()`,
  then `_fetchEntries(prov.currentPath)`
- `_buildPathBar`: add `chevron_left` / `chevron_right` IconButtons,
  styled identically to the local panel (size 16, enabled `0xFF888888`,
  disabled `0xFF333333`, `minWidth/minHeight 24`, `onPressed: null`
  when unavailable)
- Remove the Up button (amendment after initial approval): back/forward
  plus the breadcrumb cover parent navigation, so the Up button and the
  now-unused `SftpPanelProvider.navigateUp()` are deleted

### 3. Behavior

- Every navigation records history: double-click into a folder,
  breadcrumb click — standard file-manager semantics
- Host switch recreates the panel (keyed by host id), so history
  resets; the last path per host is still remembered via `initialPath`
  (existing behavior, unchanged)

## Testing

Unit tests for the history logic in `SftpPanelProvider`:

- `setPath` appends and `canGoBack`/`canGoForward` reflect position
- `goBack`/`goForward` move through history and update `currentPath`
- Pushing a new path mid-history truncates the forward stack
- Pushing the current path again (refresh) does not duplicate the entry
- `goBack`/`goForward` are no-ops at the ends of the stack

## Out of Scope

- Persisting history across host switches or app restarts
- Keyboard shortcuts for back/forward
