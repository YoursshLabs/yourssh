# Design: Workspace Persistence + Search-in-Scrollback

**Date:** 2026-05-31
**Status:** Approved
**Features:** P0 #3 (Workspace persistence) + P0 #4 (Search-in-scrollback)

---

## 1. Search-in-Scrollback

### Goal

`Cmd/Ctrl+F` opens a search bar that finds regex matches across the full terminal scrollback buffer, highlights them, and lets the user navigate between results.

### Components

**`_SearchBar` widget** — full-width bar rendered at the top of the terminal pane (inside the existing `Stack` in `_TerminalWidget.build`). Contains:
- `TextField` for query input (autofocus on open)
- Regex toggle button (`.*` icon, defaults to plain-text / case-insensitive when off)
- Prev / Next arrow buttons
- Match count label (`3 of 12`, or `No results` if zero)
- Close button (also closed by `Escape`)

**`_TerminalWidgetState` additions:**
- `final _controller = TerminalController()` — passed to `TerminalView`
- `final _scrollController = ScrollController()` — passed to `TerminalView`
- `bool _searchVisible = false`
- `String _searchQuery = ''`
- `bool _searchRegex = false`
- `List<_Match> _matches = []` where `_Match = (lineIdx, startCol, endCol)`
- `int _currentMatch = 0`
- `List<TerminalHighlight> _highlights = []`

**Search logic `_runSearch()`:**
1. Clear all existing highlights (call `dispose()` on each, clear list)
2. If query is empty, return
3. Parse as `RegExp(query, caseSensitive: false)` — if `_searchRegex` is false, escape the query first via `RegExp.escape(query)`
4. Walk `terminal.lines` (index 0 … `lines.length - 1`), extract plain text per line, find all `RegExpMatch` positions
5. For each match: create highlight via `_controller.highlight(p1: anchor(lineIdx, startCol), p2: anchor(lineIdx, endCol), color: searchHitBackground)`
6. Rebuild `_matches`; reset `_currentMatch = 0`
7. Update current-match highlight color to `searchHitBackgroundCurrent`

**Navigation:**
- `_goNext()` / `_goPrev()`: increment/decrement `_currentMatch` (wrapping), update highlight color of old vs. new current match, scroll to line: `_scrollController.animateTo(lineIdx * _lineHeight, duration: 150ms, curve: easeOut)`
- Line height estimated as `settings.fontSize * 1.2` (xterm default)

**Keyboard handling** (added to `_handleKey`):
- `Cmd/Ctrl+F` → `setState(() => _searchVisible = true)`
- `Escape` (when bar visible) → `_closeSearch()`
- `Enter` → `_goNext()`
- `Shift+Enter` → `_goPrev()`

`_closeSearch()` clears highlights, resets state, returns focus to terminal.

### Data flow

```
User types query
  → _runSearch()
    → dispose old highlights
    → walk terminal.lines
    → controller.highlight() × N
    → rebuild _matches
    → _SearchBar shows count
User presses Enter / arrow
  → _goNext() / _goPrev()
    → update current highlight color
    → scrollController.animateTo(...)
```

### Constraints

- `terminal.lines` is a `CircularBuffer` capped at `maxLines: 10000` (set in `SshSession`). Search walks all filled lines — acceptable perf for 10k lines.
- Highlights are per `TerminalController` instance (lives in widget state, not in `SshSession`), so switching tabs resets search state — intentional.
- Alt buffer (e.g., vim, htop) uses a separate buffer; search is only on `mainBuffer` (accessed via `terminal.lines` which reflects the active buffer — acceptable tradeoff).

---

## 2. Workspace Persistence

### Goal

On relaunch, the app auto-reconnects all SSH tabs that were open when it last closed, in the same order, with the same layout. Hosts that were deleted in the interim are skipped with a single consolidated warning snackbar.

### Model

```dart
class WorkspaceSnapshot {
  final List<String> hostIds;   // ordered list of host IDs to reconnect
  final String? activeHostId;   // host ID that was the active tab
  final SplitLayout layout;     // single / horizontal / vertical / quad
  final bool inputBarVisible;
}
```

Serialized as JSON in SharedPreferences under key `workspace_snapshot`.

### WorkspaceService

New file: `app/lib/services/workspace_service.dart`

```
save(WorkspaceSnapshot) → writes JSON to prefs
load() → WorkspaceSnapshot?  (returns null if key absent or JSON malformed)
clear() → removes key
```

No providers, no ChangeNotifier — pure read/write.

### Save triggers

Two complementary triggers so a crash between them loses at most ~500ms of state:

1. **SessionProvider listener** (debounced 500ms) — wired in `main.dart` after providers are initialized. Fires on tab open/close.
2. **AppLifecycleState.inactive** — `MainScreen` implements `WidgetsBindingObserver`. Fires on minimize, Cmd+Q, or backgrounding.

Both triggers call the same `_saveWorkspace()` helper that reads current state from `SessionProvider` + `TerminalLayoutProvider` and calls `WorkspaceService.save()`.

### Restore flow

Called once in `main.dart` inside `WidgetsBinding.instance.addPostFrameCallback` (after `MultiProvider` tree is mounted):

```
1. snapshot = await WorkspaceService.load()
   → null → return (fresh start)

2. found = snapshot.hostIds
     .map(id → hostProvider.allHosts.firstWhereOrNull(h => h.id == id))
     .whereNotNull()

3. missing = snapshot.hostIds.length - found.length
   → missing > 0 → AppSnack.warning(ctx, "$missing host(s) from last session no longer exist")

4. layoutProvider.setLayout(snapshot.layout)
   if snapshot.inputBarVisible → layoutProvider.toggleInputBar()

5. for host in found (in order):
     sessionProvider.connect(host)   // fire-and-forget

6. after frame: sessionProvider.setActive(snapshot.activeHostId)
   → if activeHostId not in found → setActive(found.first.id)

7. WorkspaceService.clear()
   → written fresh on next save trigger; clear avoids stale snapshot
   → if restore fails mid-way (app crash during connect), next launch starts fresh
```

### Edge cases

| Scenario | Handling |
|---|---|
| All hosts deleted | `found` is empty → skip restore entirely, clear snapshot |
| App crashes before first debounced save | At most 500ms of tab changes lost; layout recovered from last inactive trigger |
| Non-terminal nav active at quit | Restore still opens terminal view (sessions are present) |
| Host requires passphrase re-entry | Handled by existing `SshService.connect` / `StorageService` flow — no change needed |
| `activeHostId` points to deleted host | Fall back to `found.first.id` |

---

## Files changed

| File | Change |
|---|---|
| `app/lib/widgets/terminal_view.dart` | Add `TerminalController`, `ScrollController`, `_SearchBar`, search logic to `_TerminalWidgetState` |
| `app/lib/services/workspace_service.dart` | **New** — `WorkspaceService` + `WorkspaceSnapshot` |
| `app/lib/main.dart` | Wire save listeners + restore call |
| `app/lib/screens/main_screen.dart` | Implement `WidgetsBindingObserver`, add `_saveWorkspace()` |

No new providers. No changes to `SshSession`, `Host`, `TerminalLayoutProvider`, or `SessionProvider`.
