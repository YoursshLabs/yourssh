# Workspace Persistence + Search-in-Scrollback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two missing terminal essentials — auto-restore open SSH tabs on relaunch, and a Cmd/Ctrl+F search bar that finds regex matches across the full scrollback buffer.

**Architecture:** `WorkspaceService` persists a snapshot of open host IDs + layout to SharedPreferences; `MainScreen` saves on session/layout changes (debounced 500ms) and on app-inactive lifecycle, and restores on first frame. Search lives entirely in `_TerminalWidgetState`: a `TerminalController` drives highlights via xterm's highlight API, a `ScrollController` scrolls to the current match, and a full-width `_SearchBar` widget renders at the top of the terminal Stack.

**Tech Stack:** Flutter, xterm 4.0.0 (`TerminalController.highlight`, `Buffer.createAnchor`, `BufferLine.getText`), SharedPreferences, `WidgetsBindingObserver`, `dart:async` Timer debounce.

**Spec:** `docs/superpowers/specs/2026-05-31-workspace-persistence-and-search-scrollback-design.md`

---

## File Map

| File | Change |
|------|--------|
| `app/lib/services/workspace_service.dart` | **New** — `WorkspaceSnapshot` + `WorkspaceService` |
| `app/test/services/workspace_service_test.dart` | **New** — unit tests |
| `app/lib/screens/main_screen.dart` | Modify — restore + save via `WidgetsBindingObserver` |
| `app/lib/widgets/terminal_view.dart` | Modify — search state, `_runSearch`, `_SearchBar`, keyboard |

---

## Task 1: WorkspaceService + WorkspaceSnapshot

**Files:**
- Create: `app/lib/services/workspace_service.dart`

- [ ] **Step 1: Write the file**

```dart
// app/lib/services/workspace_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/terminal_layout_provider.dart';

class WorkspaceSnapshot {
  final List<String> hostIds;
  final String? activeHostId;
  final SplitLayout layout;
  final bool inputBarVisible;

  const WorkspaceSnapshot({
    required this.hostIds,
    required this.activeHostId,
    required this.layout,
    required this.inputBarVisible,
  });

  Map<String, dynamic> toJson() => {
        'hostIds': hostIds,
        'activeHostId': activeHostId,
        'layout': layout.name,
        'inputBarVisible': inputBarVisible,
      };

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) =>
      WorkspaceSnapshot(
        hostIds: List<String>.from(json['hostIds'] as List),
        activeHostId: json['activeHostId'] as String?,
        layout: SplitLayout.values.firstWhere(
          (e) => e.name == json['layout'],
          orElse: () => SplitLayout.single,
        ),
        inputBarVisible: (json['inputBarVisible'] as bool?) ?? false,
      );
}

class WorkspaceService {
  static const _key = 'workspace_snapshot';

  Future<void> save(WorkspaceSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<WorkspaceSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return WorkspaceSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
```

- [ ] **Step 2: Run analyze to confirm no issues**

```bash
cd app && flutter analyze lib/services/workspace_service.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/workspace_service.dart
git commit -m "feat: add WorkspaceService and WorkspaceSnapshot model"
```

---

## Task 2: Tests for WorkspaceService

**Files:**
- Create: `app/test/services/workspace_service_test.dart`

- [ ] **Step 1: Write tests**

```dart
// app/test/services/workspace_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/workspace_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WorkspaceSnapshot.toJson / fromJson', () {
    test('round-trips all fields', () {
      const snap = WorkspaceSnapshot(
        hostIds: ['id-1', 'id-2'],
        activeHostId: 'id-1',
        layout: SplitLayout.horizontal,
        inputBarVisible: true,
      );
      final restored = WorkspaceSnapshot.fromJson(snap.toJson());
      expect(restored.hostIds, snap.hostIds);
      expect(restored.activeHostId, snap.activeHostId);
      expect(restored.layout, snap.layout);
      expect(restored.inputBarVisible, snap.inputBarVisible);
    });

    test('fromJson: missing activeHostId → null', () {
      final snap = WorkspaceSnapshot.fromJson({
        'hostIds': <String>[],
        'layout': 'single',
        'inputBarVisible': false,
      });
      expect(snap.activeHostId, isNull);
    });

    test('fromJson: unknown layout → SplitLayout.single', () {
      final snap = WorkspaceSnapshot.fromJson({
        'hostIds': <String>[],
        'activeHostId': null,
        'layout': 'unknown_value',
        'inputBarVisible': false,
      });
      expect(snap.layout, SplitLayout.single);
    });

    test('fromJson: missing inputBarVisible → false', () {
      final snap = WorkspaceSnapshot.fromJson({
        'hostIds': <String>[],
        'activeHostId': null,
        'layout': 'single',
      });
      expect(snap.inputBarVisible, isFalse);
    });
  });

  group('WorkspaceService', () {
    test('load returns null when key absent', () async {
      expect(await WorkspaceService().load(), isNull);
    });

    test('save then load round-trips snapshot', () async {
      const snap = WorkspaceSnapshot(
        hostIds: ['a', 'b'],
        activeHostId: 'a',
        layout: SplitLayout.vertical,
        inputBarVisible: false,
      );
      await WorkspaceService().save(snap);
      final loaded = await WorkspaceService().load();
      expect(loaded?.hostIds, ['a', 'b']);
      expect(loaded?.layout, SplitLayout.vertical);
      expect(loaded?.activeHostId, 'a');
    });

    test('clear makes load return null', () async {
      await WorkspaceService().save(const WorkspaceSnapshot(
        hostIds: ['x'],
        activeHostId: null,
        layout: SplitLayout.single,
        inputBarVisible: false,
      ));
      await WorkspaceService().clear();
      expect(await WorkspaceService().load(), isNull);
    });

    test('load returns null for malformed JSON', () async {
      SharedPreferences.setMockInitialValues(
          {'workspace_snapshot': 'not-valid-json{{'});
      expect(await WorkspaceService().load(), isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect all pass**

```bash
cd app && flutter test test/services/workspace_service_test.dart -v
```

Expected: all 8 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/test/services/workspace_service_test.dart
git commit -m "test: workspace_service round-trip and edge cases"
```

---

## Task 3: Workspace restore on launch

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add imports at top of main_screen.dart**

After the existing imports, add:

```dart
import 'dart:async';
import '../services/workspace_service.dart';
import '../providers/host_provider.dart';
```

Note: `HostProvider` may already be imported — check and skip if so.

- [ ] **Step 2: Add `_WorkspaceService` field to `_MainScreenState` and `WidgetsBindingObserver`**

Change:
```dart
class _MainScreenState extends State<MainScreen> {
```
To:
```dart
class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _workspaceSvc = WorkspaceService();
  Timer? _workspaceSaveDebounce;
```

- [ ] **Step 3: Register / unregister observer in initState / dispose**

In `initState`, add after `super.initState()`:
```dart
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreWorkspace());
```

In `dispose`, add before `super.dispose()`:
```dart
    WidgetsBinding.instance.removeObserver(this);
    _workspaceSaveDebounce?.cancel();
```

- [ ] **Step 4: Add `_restoreWorkspace()` method**

Add this method to `_MainScreenState`:

```dart
Future<void> _restoreWorkspace() async {
  final snapshot = await _workspaceSvc.load();
  if (snapshot == null || !mounted) return;

  final hostProvider = context.read<HostProvider>();
  final sessionProvider = context.read<SessionProvider>();
  final layoutProvider = context.read<TerminalLayoutProvider>();

  final allHosts = hostProvider.allHosts;
  final found = snapshot.hostIds
      .map((id) => allHosts.where((h) => h.id == id).firstOrNull)
      .whereType<Host>()
      .toList();

  final missingCount = snapshot.hostIds.length - found.length;
  if (missingCount > 0 && mounted) {
    AppSnack.info(context,
        '$missingCount host(s) from last session no longer exist');
  }

  if (found.isEmpty) {
    await _workspaceSvc.clear();
    return;
  }

  layoutProvider.setLayout(snapshot.layout);
  if (snapshot.inputBarVisible != layoutProvider.inputBarVisible) {
    layoutProvider.toggleInputBar();
  }

  for (final host in found) {
    unawaited(sessionProvider.connect(host));
  }

  // Sessions are added synchronously at start of connect(); set active now.
  if (snapshot.activeHostId != null) {
    final targetSession = sessionProvider.sessions
        .where((s) => s.host.id == snapshot.activeHostId)
        .firstOrNull;
    if (targetSession != null) {
      sessionProvider.setActive(targetSession.id);
    }
  }

  await _workspaceSvc.clear();
}
```

- [ ] **Step 5: Run app and verify restore flow works with no saved snapshot (cold start)**

```bash
cd app && flutter run -d macos
```

Expected: app starts normally, no crash, no snackbar.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: restore workspace sessions and layout on app launch"
```

---

## Task 4: Workspace save triggers

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Track TerminalLayoutProvider in `_MainScreenState`**

Add field:
```dart
  TerminalLayoutProvider? _layoutProvider;
```

In `didChangeDependencies`, after the existing `_knownHostsProvider` tracking block, add:

```dart
    final layout = context.read<TerminalLayoutProvider>();
    if (_layoutProvider != layout) {
      _layoutProvider?.removeListener(_onLayoutChangedForSave);
      _layoutProvider = layout;
      layout.addListener(_onLayoutChangedForSave);
    }
```

In `dispose`, before `super.dispose()`, add:
```dart
    _layoutProvider?.removeListener(_onLayoutChangedForSave);
```

- [ ] **Step 2: Add save helpers**

Add these methods to `_MainScreenState`:

```dart
void _onLayoutChangedForSave() => _scheduleSave();
void _onSessionsChangedForSave() => _scheduleSave();

void _scheduleSave() {
  _workspaceSaveDebounce?.cancel();
  _workspaceSaveDebounce = Timer(
    const Duration(milliseconds: 500),
    _saveWorkspaceNow,
  );
}

void _saveWorkspaceNow() {
  final sessions = _sessionProvider?.sessions;
  final layout = _layoutProvider;
  if (sessions == null || layout == null) return;
  final snapshot = WorkspaceSnapshot(
    hostIds: sessions.map((s) => s.host.id).toList(),
    activeHostId: _sessionProvider?.activeSession?.host.id,
    layout: layout.layout,
    inputBarVisible: layout.inputBarVisible,
  );
  _workspaceSvc.save(snapshot);
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.inactive) _saveWorkspaceNow();
}
```

- [ ] **Step 3: Wire session listener for saves**

The existing `_sessionProvider` listener in `didChangeDependencies` currently calls `_onSessionsChanged`. Add the workspace save listener alongside it:

Change the tracking block in `didChangeDependencies` from:
```dart
    final provider = context.read<SessionProvider>();
    if (_sessionProvider != provider) {
      _sessionProvider?.removeListener(_onSessionsChanged);
      _sessionProvider = provider;
      provider.addListener(_onSessionsChanged);
    }
```
To:
```dart
    final provider = context.read<SessionProvider>();
    if (_sessionProvider != provider) {
      _sessionProvider?.removeListener(_onSessionsChanged);
      _sessionProvider?.removeListener(_onSessionsChangedForSave);
      _sessionProvider = provider;
      provider.addListener(_onSessionsChanged);
      provider.addListener(_onSessionsChangedForSave);
    }
```

And in `dispose`:
```dart
    _sessionProvider?.removeListener(_onSessionsChangedForSave);
```

- [ ] **Step 4: Test save + restore manually**

```bash
cd app && flutter run -d macos
```

1. Connect to 1-2 SSH hosts
2. Quit the app (Cmd+Q)
3. Relaunch
4. Expected: same SSH tabs open and auto-reconnecting

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: save workspace on session/layout change and app-inactive"
```

---

## Task 5: TerminalController + ScrollController wiring

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1: Add xterm controller imports**

`terminal_view.dart` already imports `package:xterm/xterm.dart`. No new imports needed.

- [ ] **Step 2: Add controller and scroll state fields to `_TerminalWidgetState`**

Add these fields:

```dart
  final _controller = TerminalController();
  final _scrollController = ScrollController();

  // Search state
  bool _searchVisible = false;
  String _searchQuery = '';
  bool _searchRegex = false;
  bool _searchError = false;
  List<_SearchMatch> _matches = [];
  int _currentMatch = 0;
  final List<TerminalHighlight> _highlights = [];
  late final TextEditingController _searchTextController;
```

- [ ] **Step 3: Initialize and dispose controllers in initState / dispose**

Add `@override initState`:
```dart
  @override
  void initState() {
    super.initState();
    _searchTextController = TextEditingController();
  }
```

Add `@override dispose`:
```dart
  @override
  void dispose() {
    _clearHighlights();
    _controller.dispose();
    _scrollController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Define `_SearchMatch` private class**

Add this private class at the bottom of `terminal_view.dart` (outside any other class):

```dart
class _SearchMatch {
  final int lineIdx;
  final int startCol;
  final int endCol;
  const _SearchMatch(this.lineIdx, this.startCol, this.endCol);
}
```

- [ ] **Step 5: Pass controller and scrollController to TerminalView**

In `_TerminalWidgetState.build`, change:
```dart
        TerminalView(
          widget.session.terminal,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
          padding: EdgeInsets.zero,
          autofocus: true,
          onKeyEvent: _handleKey,
        ),
```
To:
```dart
        TerminalView(
          widget.session.terminal,
          controller: _controller,
          scrollController: _scrollController,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
          padding: EdgeInsets.zero,
          autofocus: !_searchVisible,
          onKeyEvent: _handleKey,
        ),
```

- [ ] **Step 6: Run analyze to catch any type errors**

```bash
cd app && flutter analyze lib/widgets/terminal_view.dart
```

Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: wire TerminalController and ScrollController to terminal view"
```

---

## Task 6: _runSearch() and navigation logic

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1: Add `_clearHighlights()` helper**

Add to `_TerminalWidgetState`:

```dart
  void _clearHighlights() {
    for (final h in _highlights) {
      h.dispose();
    }
    _highlights.clear();
  }
```

- [ ] **Step 2: Add `_runSearch()` method**

Add to `_TerminalWidgetState`:

```dart
  void _runSearch() {
    _clearHighlights();

    if (_searchQuery.isEmpty) {
      setState(() {
        _matches = [];
        _currentMatch = 0;
        _searchError = false;
      });
      return;
    }

    RegExp regex;
    try {
      final pattern =
          _searchRegex ? _searchQuery : RegExp.escape(_searchQuery);
      regex = RegExp(pattern, caseSensitive: false);
    } catch (_) {
      setState(() {
        _matches = [];
        _currentMatch = 0;
        _searchError = true;
      });
      return;
    }

    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final lines = terminal.lines;
    final newMatches = <_SearchMatch>[];

    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].getText();
      for (final m in regex.allMatches(text)) {
        newMatches.add(_SearchMatch(i, m.start, m.end));
      }
    }

    final theme = context.read<SettingsProvider>();
    final termTheme = terminalThemeByName(theme.terminalTheme);

    for (var mi = 0; mi < newMatches.length; mi++) {
      final match = newMatches[mi];
      final color = mi == 0
          ? termTheme.searchHitBackgroundCurrent
          : termTheme.searchHitBackground;
      final h = _controller.highlight(
        p1: buffer.createAnchor(match.startCol, match.lineIdx),
        p2: buffer.createAnchor(match.endCol, match.lineIdx),
        color: color,
      );
      _highlights.add(h);
    }

    setState(() {
      _matches = newMatches;
      _currentMatch = 0;
      _searchError = false;
    });

    if (newMatches.isNotEmpty) _scrollToMatch(0);
  }
```

- [ ] **Step 3: Add `_scrollToMatch()` helper**

Add to `_TerminalWidgetState`:

```dart
  void _scrollToMatch(int matchIdx) {
    if (_matches.isEmpty || !_scrollController.hasClients) return;
    final lineIdx = _matches[matchIdx].lineIdx;
    final fontSize = context.read<SettingsProvider>().fontSize;
    final estimatedLineHeight = fontSize * 1.35;
    final offset = (lineIdx * estimatedLineHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }
```

- [ ] **Step 4: Add `_goNext()` and `_goPrev()` methods**

Add to `_TerminalWidgetState`:

```dart
  void _goNext() {
    if (_matches.isEmpty) return;
    final termTheme =
        terminalThemeByName(context.read<SettingsProvider>().terminalTheme);
    // Reset current match to normal color
    _highlights[_currentMatch].dispose();
    final old = _matches[_currentMatch];
    final restored = _controller.highlight(
      p1: widget.session.terminal.buffer.createAnchor(old.startCol, old.lineIdx),
      p2: widget.session.terminal.buffer.createAnchor(old.endCol, old.lineIdx),
      color: termTheme.searchHitBackground,
    );
    _highlights[_currentMatch] = restored;

    final next = (_currentMatch + 1) % _matches.length;
    // Highlight new current match
    _highlights[next].dispose();
    final cur = _matches[next];
    final newH = _controller.highlight(
      p1: widget.session.terminal.buffer.createAnchor(cur.startCol, cur.lineIdx),
      p2: widget.session.terminal.buffer.createAnchor(cur.endCol, cur.lineIdx),
      color: termTheme.searchHitBackgroundCurrent,
    );
    _highlights[next] = newH;

    setState(() => _currentMatch = next);
    _scrollToMatch(next);
  }

  void _goPrev() {
    if (_matches.isEmpty) return;
    final termTheme =
        terminalThemeByName(context.read<SettingsProvider>().terminalTheme);
    _highlights[_currentMatch].dispose();
    final old = _matches[_currentMatch];
    final restored = _controller.highlight(
      p1: widget.session.terminal.buffer.createAnchor(old.startCol, old.lineIdx),
      p2: widget.session.terminal.buffer.createAnchor(old.endCol, old.lineIdx),
      color: termTheme.searchHitBackground,
    );
    _highlights[_currentMatch] = restored;

    final prev =
        (_currentMatch - 1 + _matches.length) % _matches.length;
    _highlights[prev].dispose();
    final cur = _matches[prev];
    final newH = _controller.highlight(
      p1: widget.session.terminal.buffer.createAnchor(cur.startCol, cur.lineIdx),
      p2: widget.session.terminal.buffer.createAnchor(cur.endCol, cur.lineIdx),
      color: termTheme.searchHitBackgroundCurrent,
    );
    _highlights[prev] = newH;

    setState(() => _currentMatch = prev);
    _scrollToMatch(prev);
  }
```

- [ ] **Step 5: Add `_closeSearch()` method**

Add to `_TerminalWidgetState`:

```dart
  void _closeSearch() {
    _clearHighlights();
    _searchTextController.clear();
    setState(() {
      _searchVisible = false;
      _searchQuery = '';
      _searchRegex = false;
      _searchError = false;
      _matches = [];
      _currentMatch = 0;
    });
  }
```

- [ ] **Step 6: Run analyze**

```bash
cd app && flutter analyze lib/widgets/terminal_view.dart
```

Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: implement search logic with regex, highlights, and scroll navigation"
```

---

## Task 7: _SearchBar widget

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1: Add `_SearchBar` widget class at end of file**

Add after `_RecordButton`:

```dart
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool useRegex;
  final bool hasError;
  final int matchCount;
  final int currentMatch;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleRegex;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  const _SearchBar({
    required this.controller,
    required this.useRegex,
    required this.hasError,
    required this.matchCount,
    required this.currentMatch,
    required this.onQueryChanged,
    required this.onToggleRegex,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasResults = matchCount > 0;
    final countLabel = controller.text.isEmpty
        ? ''
        : hasError
            ? 'Invalid regex'
            : hasResults
                ? '${currentMatch + 1} of $matchCount'
                : 'No results';
    final countColor = hasError
        ? Colors.red
        : hasResults
            ? const Color(0xFF888888)
            : Colors.orange;

    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onQueryChanged,
              style: const TextStyle(
                color: Color(0xFFEEEEEE),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: useRegex ? 'Search (regex)…' : 'Search…',
                hintStyle: const TextStyle(
                    color: Color(0xFF555555), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (countLabel.isNotEmpty)
            Text(
              countLabel,
              style: TextStyle(
                color: countColor,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          const SizedBox(width: 8),
          _SearchBtn(
            tooltip: 'Use regex',
            active: useRegex,
            label: '.*',
            onTap: onToggleRegex,
          ),
          const SizedBox(width: 4),
          _SearchBtn(
            tooltip: 'Previous match (Shift+Enter)',
            icon: Icons.keyboard_arrow_up,
            onTap: onPrev,
          ),
          const SizedBox(width: 2),
          _SearchBtn(
            tooltip: 'Next match (Enter)',
            icon: Icons.keyboard_arrow_down,
            onTap: onNext,
          ),
          const SizedBox(width: 4),
          _SearchBtn(
            tooltip: 'Close search (Escape)',
            icon: Icons.close,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _SearchBtn extends StatefulWidget {
  final String? tooltip;
  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const _SearchBtn({
    this.tooltip,
    this.label,
    this.icon,
    this.active = false,
    required this.onTap,
  }) : assert(label != null || icon != null);

  @override
  State<_SearchBtn> createState() => _SearchBtnState();
}

class _SearchBtnState extends State<_SearchBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? const Color(0xFF4FC3F7)
        : _hovered
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666);

    final child = widget.label != null
        ? Text(
            widget.label!,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600),
          )
        : Icon(widget.icon, size: 14, color: color);

    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.active
                  ? const Color(0xFF4FC3F7).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire `_SearchBar` into `_TerminalWidgetState.build`**

In the `build` method, change the `Stack` children to include the search bar at top. Replace the existing `Stack`:

```dart
    return Stack(
      children: [
        TerminalView(
          widget.session.terminal,
          controller: _controller,
          scrollController: _scrollController,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
          padding: EdgeInsets.zero,
          autofocus: !_searchVisible,
          onKeyEvent: _handleKey,
        ),
        if (_searchVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _SearchBar(
              controller: _searchTextController,
              useRegex: _searchRegex,
              hasError: _searchError,
              matchCount: _matches.length,
              currentMatch: _currentMatch,
              onQueryChanged: (q) {
                _searchQuery = q;
                _runSearch();
              },
              onToggleRegex: () {
                setState(() => _searchRegex = !_searchRegex);
                _runSearch();
              },
              onNext: _goNext,
              onPrev: _goPrev,
              onClose: _closeSearch,
            ),
          ),
        Positioned(
          top: _searchVisible ? 44 : 8,
          left: 8,
          child: _RecordButton(session: widget.session),
        ),
        if (_suggestions.isNotEmpty)
          Positioned(
            bottom: 8,
            right: 8,
            width: 320,
            child: SuggestionPopup(
              suggestions: _suggestions,
              selectedIndex: _selectedIdx,
              onSelect: _completeTo,
            ),
          ),
      ],
    );
```

- [ ] **Step 3: Run analyze**

```bash
cd app && flutter analyze lib/widgets/terminal_view.dart
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: add _SearchBar widget with regex toggle, nav, and match count"
```

---

## Task 8: Keyboard handler for search

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1: Update `_handleKey` to intercept search shortcuts**

In `_TerminalWidgetState._handleKey`, at the very top of the method body (before any other checks), add:

```dart
    final meta = HardwareKeyboard.instance.isMetaPressed;
    // (ctrl is already declared below — read it early too)
    final ctrl2 = HardwareKeyboard.instance.isControlPressed;

    // Open search (Cmd+F / Ctrl+F)
    if ((meta || ctrl2) && key == LogicalKeyboardKey.keyF) {
      setState(() => _searchVisible = true);
      return KeyEventResult.handled;
    }

    // Search bar keyboard shortcuts when visible
    if (_searchVisible) {
      if (key == LogicalKeyboardKey.escape) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _goPrev();
        } else {
          _goNext();
        }
        return KeyEventResult.handled;
      }
      // All other keys go to the search TextField, not the terminal
      return KeyEventResult.ignored;
    }
```

Note: remove the duplicate `final ctrl` and `final meta` declarations that come later in the existing method (or rename them to avoid conflicts). The existing `_handleKey` already declares `final ctrl` and `final meta` — remove those two lines since we moved them to the top, or rename the ones added above to avoid double-declaration.

To be precise: the existing `_handleKey` is:
```dart
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    ...
```

Replace the entire `_handleKey` with:

```dart
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;

    // Open search (Cmd+F on macOS, Ctrl+F elsewhere)
    if ((meta || ctrl) && key == LogicalKeyboardKey.keyF) {
      setState(() => _searchVisible = true);
      return KeyEventResult.handled;
    }

    // While search bar is visible: intercept Escape and Enter only;
    // all other keys flow to the TextField via its own focus.
    if (_searchVisible) {
      if (key == LogicalKeyboardKey.escape) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _goPrev();
        } else {
          _goNext();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.tab) {
      if (_suggestions.isNotEmpty) {
        _completeTo(_suggestions[_selectedIdx]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _selectedIdx = (_selectedIdx - 1).clamp(0, _suggestions.length - 1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _selectedIdx = (_selectedIdx + 1).clamp(0, _suggestions.length - 1));
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.enter ||
        (ctrl && key == LogicalKeyboardKey.keyC) ||
        (ctrl && key == LogicalKeyboardKey.keyU)) {
      setState(() {
        _inputBuffer = '';
        _suggestions = [];
      });
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.backspace) {
      if (_inputBuffer.isNotEmpty) {
        setState(() => _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1));
        _refreshSuggestions();
      }
      return KeyEventResult.ignored;
    }

    if (!ctrl && !meta) {
      final char = event.character;
      if (char != null && char.length == 1 && char.codeUnitAt(0) >= 0x20) {
        _inputBuffer += char;
        _refreshSuggestions();
      }
    }

    return KeyEventResult.ignored;
  }
```

- [ ] **Step 2: Run analyze**

```bash
cd app && flutter analyze lib/widgets/terminal_view.dart
```

Expected: no issues.

- [ ] **Step 3: Run the app and verify search end-to-end**

```bash
cd app && flutter run -d macos
```

Manual test checklist:
1. Connect to an SSH host
2. Run `ls -la` or any command that produces output
3. Press Cmd+F — search bar appears at top of terminal
4. Type a search term — matches highlight in yellow/orange
5. Press Enter — jumps to next match, count shows `2 of N`
6. Press Shift+Enter — jumps to previous match
7. Click `.*` button — activates regex mode; type `[a-z]+` to verify regex matching
8. Type invalid regex `(` — shows "Invalid regex" in red
9. Press Escape — search bar closes, highlights clear
10. Press Cmd+F again — search bar reopens empty

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: Cmd/Ctrl+F search-in-scrollback with regex, navigation, and keyboard shortcuts"
```

---

## Task 9: Final verify + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass including the new workspace_service tests.

- [ ] **Step 2: Run flutter analyze on all changed files**

```bash
cd app && flutter analyze lib/services/workspace_service.dart lib/screens/main_screen.dart lib/widgets/terminal_view.dart
```

Expected: no issues.

- [ ] **Step 3: Update CHANGELOG.md**

Move items from `[Unreleased]` into a new `[0.1.7]` section (or add to [Unreleased] if not bumping version):

```markdown
## [Unreleased]

### Added
- Search-in-scrollback (`Cmd/Ctrl+F`): regex support, case-insensitive toggle, prev/next navigation, match count, highlight via xterm TerminalController
- Workspace persistence: app auto-reconnects all open SSH tabs on relaunch with saved layout; shows warning for hosts that no longer exist
```

- [ ] **Step 4: Final commit**

```bash
git add CHANGELOG.md
git commit -m "docs: update CHANGELOG for workspace persistence and search-in-scrollback"
```
