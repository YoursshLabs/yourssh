# Advanced Tab Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rename, color tag, pin, and drag reorder to the SSH session tab bar, with all metadata persisting per host via SharedPreferences.

**Architecture:** Extend `SshSession` with three mutable runtime fields (`customLabel`, `colorTag`, `isPinned`). A new `TabMetadataService` persists metadata keyed by `hostId` to SharedPreferences (same pattern as `WorkspaceService`). `SessionProvider` gains four new mutator methods and loads metadata on `connect()`. `_SessionTab` in `main_screen.dart` gains a color dot, pin icon, inline rename, and right-click context menu. `_TopTabBar` replaces `ListView` with `ReorderableListView` for drag reorder.

**Tech Stack:** Flutter, Dart, `shared_preferences`, `flutter_test`, `ReorderableListView` (Flutter built-in)

---

## Task 1: SshSession — add tab metadata fields

**Files:**
- Modify: `app/lib/models/ssh_session.dart`
- Test: `app/test/models/ssh_session_test.dart`

- [ ] **Step 1: Write failing tests**

Create `app/test/models/ssh_session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

Host _host() => Host(id: 'h1', label: 'prod', host: 'prod.example.com', port: 22, username: 'alice');

void main() {
  group('SshSession tab metadata fields', () {
    test('defaults: customLabel null, colorTag null, isPinned false', () {
      final s = SshSession(host: _host());
      expect(s.customLabel, isNull);
      expect(s.colorTag, isNull);
      expect(s.isPinned, isFalse);
    });

    test('title returns customLabel when set', () {
      final s = SshSession(host: _host());
      s.customLabel = 'my-prod';
      expect(s.title, 'my-prod');
    });

    test('title falls back to user@host when customLabel is null', () {
      final s = SshSession(host: _host());
      expect(s.title, 'alice@prod.example.com');
    });

    test('title falls back to user@host when customLabel is cleared to null', () {
      final s = SshSession(host: _host());
      s.customLabel = 'custom';
      s.customLabel = null;
      expect(s.title, 'alice@prod.example.com');
    });

    test('colorTag can be set and cleared', () {
      final s = SshSession(host: _host());
      s.colorTag = '#ef4444';
      expect(s.colorTag, '#ef4444');
      s.colorTag = null;
      expect(s.colorTag, isNull);
    });

    test('isPinned can be toggled', () {
      final s = SshSession(host: _host());
      s.isPinned = true;
      expect(s.isPinned, isTrue);
      s.isPinned = false;
      expect(s.isPinned, isFalse);
    });

    test('watch session title is not affected by customLabel logic', () {
      final s = SshSession.watch(watchedTitle: 'alice@prod.example.com');
      expect(s.title, '[WATCH] alice@prod.example.com');
      s.customLabel = 'renamed';
      expect(s.title, 'renamed');
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/models/ssh_session_test.dart
```

Expected: compile error — `customLabel`, `colorTag`, `isPinned` not defined on `SshSession`.

- [ ] **Step 3: Add fields to SshSession**

Edit `app/lib/models/ssh_session.dart`:

```dart
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import 'host.dart';

enum SessionStatus { connecting, connected, disconnected, error }

class SshSession {
  final String id;
  final Host host;
  final Terminal terminal;
  SessionStatus status;
  String? errorMessage;
  DateTime connectedAt;
  final String? initialCommand;
  final bool isWatch;
  final String? watchedTitle;
  String? customLabel;
  String? colorTag;
  bool isPinned;

  SshSession({
    String? id,
    required this.host,
    this.status = SessionStatus.connecting,
    this.errorMessage,
    DateTime? connectedAt,
    this.initialCommand,
    this.isWatch = false,
    this.watchedTitle,
    this.customLabel,
    this.colorTag,
    this.isPinned = false,
  })  : id = id ?? const Uuid().v4(),
        terminal = Terminal(maxLines: 10000),
        connectedAt = connectedAt ?? DateTime.now();

  factory SshSession.watch({required String watchedTitle}) {
    return SshSession(
      host: Host(
        id: const Uuid().v4(),
        label: '[WATCH] $watchedTitle',
        host: '',
        port: 22,
        username: '',
      ),
      status: SessionStatus.connected,
      isWatch: true,
      watchedTitle: watchedTitle,
    );
  }

  String get title =>
      customLabel ??
      (isWatch ? '[WATCH] ${watchedTitle ?? host.host}' : '${host.username}@${host.host}');

  String get statusLabel => switch (status) {
        SessionStatus.connecting => 'Connecting...',
        SessionStatus.connected => isWatch ? 'Watching' : 'Connected',
        SessionStatus.disconnected => 'Disconnected',
        SessionStatus.error => errorMessage ?? 'Error',
      };
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/models/ssh_session_test.dart
```

Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/ssh_session.dart app/test/models/ssh_session_test.dart
git commit -m "feat(tabs): add customLabel, colorTag, isPinned to SshSession"
```

---

## Task 2: TabMetadataService — new service

**Files:**
- Create: `app/lib/services/tab_metadata_service.dart`
- Create: `app/test/services/tab_metadata_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `app/test/services/tab_metadata_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('TabMetadataService', () {
    test('loadMetadata returns null when no data stored', () async {
      final result = await TabMetadataService().loadMetadata('host-1');
      expect(result, isNull);
    });

    test('saveMetadata then loadMetadata round-trips all fields', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: 'my-prod', color: '#ef4444', pinned: true);
      final result = await svc.loadMetadata('host-1');
      expect(result?['label'], 'my-prod');
      expect(result?['color'], '#ef4444');
      expect(result?['pinned'], isTrue);
    });

    test('saveMetadata with null fields omits those keys', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: null, color: null, pinned: false);
      final result = await svc.loadMetadata('host-1');
      expect(result?['label'], isNull);
      expect(result?['color'], isNull);
      expect(result?['pinned'], isFalse);
    });

    test('saveMetadata is per-host — different hosts do not interfere', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: 'alpha', color: '#3b82f6', pinned: true);
      await svc.saveMetadata('host-2', label: 'beta', color: null, pinned: false);
      expect((await svc.loadMetadata('host-1'))?['label'], 'alpha');
      expect((await svc.loadMetadata('host-2'))?['label'], 'beta');
    });

    test('clearMetadata removes the stored data', () async {
      final svc = TabMetadataService();
      await svc.saveMetadata('host-1', label: 'x', color: null, pinned: false);
      await svc.clearMetadata('host-1');
      expect(await svc.loadMetadata('host-1'), isNull);
    });

    test('loadMetadata returns null for malformed JSON', () async {
      SharedPreferences.setMockInitialValues({'tab_meta_host-1': 'not-json{{'});
      final result = await TabMetadataService().loadMetadata('host-1');
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect compile error**

```bash
cd app && flutter test test/services/tab_metadata_service_test.dart
```

Expected: compile error — `TabMetadataService` not found.

- [ ] **Step 3: Implement TabMetadataService**

Create `app/lib/services/tab_metadata_service.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TabMetadataService {
  static String _key(String hostId) => 'tab_meta_$hostId';

  Future<void> saveMetadata(
    String hostId, {
    required String? label,
    required String? color,
    required bool pinned,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(hostId),
      jsonEncode({'label': label, 'color': color, 'pinned': pinned}),
    );
  }

  Future<Map<String, dynamic>?> loadMetadata(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(hostId));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[TabMetadataService] malformed metadata for $hostId: $e');
      return null;
    }
  }

  Future<void> clearMetadata(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(hostId));
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/services/tab_metadata_service_test.dart
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/tab_metadata_service.dart app/test/services/tab_metadata_service_test.dart
git commit -m "feat(tabs): add TabMetadataService for per-host tab metadata persistence"
```

---

## Task 3: SessionProvider — inject TabMetadataService + load on connect

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Modify: `app/lib/main.dart` (line ~128)
- Modify: `app/test/providers/session_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Append to the `setUp` block and add a new group in `app/test/providers/session_provider_test.dart`. Find the existing `setUp` that creates `provider = SessionProvider(SshService(StorageService()))` and note that after this change the constructor will require a second argument.

Add these tests inside `group('SessionProvider', ...)`:

```dart
test('loadMetadata applied to session on connect (mocked via SharedPreferences)', () async {
  SharedPreferences.setMockInitialValues({
    'tab_meta_h-load': jsonEncode({
      'label': 'saved-label',
      'color': '#22c55e',
      'pinned': true,
    }),
  });
  final p = SessionProvider(SshService(StorageService()), TabMetadataService());
  final host = Host(
    id: 'h-load',
    label: 'Test',
    host: '1.2.3.4',
    port: 22,
    username: 'user',
  );
  // SSH will fail (no real server) but metadata is loaded before _doConnect.
  // connect() catches all SSH exceptions internally, so await completes cleanly.
  await p.connect(host);
  final session = p.sessions.first;
  expect(session.customLabel, 'saved-label');
  expect(session.colorTag, '#22c55e');
  expect(session.isPinned, isTrue);
  p.dispose();
});
```

Also add `import 'dart:convert';` and `import 'package:yourssh/services/tab_metadata_service.dart';` at the top.

- [ ] **Step 2: Update existing SessionProvider setUp to pass TabMetadataService**

In `app/test/providers/session_provider_test.dart`, find:

```dart
provider = SessionProvider(SshService(StorageService()));
```

Replace with:

```dart
provider = SessionProvider(SshService(StorageService()), TabMetadataService());
```

- [ ] **Step 3: Run tests — expect compile error**

```bash
cd app && flutter test test/providers/session_provider_test.dart
```

Expected: compile error — `SessionProvider` constructor doesn't accept `TabMetadataService`.

- [ ] **Step 4: Update SessionProvider constructor**

In `app/lib/providers/session_provider.dart`, add the import and field, then update the constructor:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import '../services/ssh_service.dart';
import '../services/tab_metadata_service.dart';

class SessionProvider extends ChangeNotifier {
  final SshService _ssh;
  final TabMetadataService _tabMetadata;
  // ... rest unchanged
```

Update constructor:

```dart
SessionProvider(this._ssh, this._tabMetadata);
```

Update `connect()` to load metadata after session creation:

```dart
Future<void> connect(Host host, {String? initialCommand}) async {
  final session = SshSession(host: host, initialCommand: initialCommand);
  _sessions.add(session);
  _activeSessionId = session.id;
  _safeNotify();

  // Load persisted tab metadata (label, color, pin) for this host.
  final meta = await _tabMetadata.loadMetadata(host.id);
  if (meta != null) {
    session.customLabel = meta['label'] as String?;
    session.colorTag = meta['color'] as String?;
    session.isPinned = (meta['pinned'] as bool?) ?? false;
    if (session.isPinned) _sortSessions();
    _safeNotify();
  }

  await _doConnect(session, host, attempt: 1);
}
```

Add `_sortSessions()` helper at the bottom of `SessionProvider` (before the closing `}`):

```dart
void _sortSessions() {
  final pinned = _sessions.where((s) => s.isPinned).toList();
  final unpinned = _sessions.where((s) => !s.isPinned).toList();
  _sessions
    ..clear()
    ..addAll(pinned)
    ..addAll(unpinned);
}
```

- [ ] **Step 5: Update main.dart**

In `app/lib/main.dart`, find line ~128:

```dart
_sessionProvider = SessionProvider(_ssh);
```

Add the import at the top of the file:

```dart
import 'services/tab_metadata_service.dart';
```

Update the instantiation:

```dart
_sessionProvider = SessionProvider(_ssh, TabMetadataService());
```

- [ ] **Step 6: Run tests — expect pass**

```bash
cd app && flutter test test/providers/session_provider_test.dart
```

Expected: All existing tests plus new metadata test pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/providers/session_provider.dart app/lib/main.dart app/test/providers/session_provider_test.dart
git commit -m "feat(tabs): inject TabMetadataService into SessionProvider; load metadata on connect"
```

---

## Task 4: SessionProvider — renameSession, setSessionColor, togglePin, reorderSession

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Modify: `app/test/providers/session_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Append a new group to `app/test/providers/session_provider_test.dart`. You'll need helper `Host` and `SshSession` factories — add them at the top of `main()` or as top-level helpers:

```dart
Host _makeHost(String id) => Host(
  id: id, label: id, host: '$id.example.com', port: 22, username: 'user',
);

SshSession _makeSession(String hostId) =>
    SshSession(host: _makeHost(hostId));
```

Add tests:

```dart
group('tab metadata mutations', () {
  late SessionProvider p;

  setUp(() {
    p = SessionProvider(SshService(StorageService()), TabMetadataService());
    // Inject sessions directly via addWatchSession trick is not available,
    // so we manually insert into the sessions list via the connect path
    // is async. Instead, use a package-private accessor exposed for tests,
    // or test via the public sessions list after adding watch sessions.
    //
    // For unit testing mutations, add a watch session as a stand-in.
    p.addWatchSession(_makeSession('h1'));
    p.addWatchSession(_makeSession('h2'));
    p.addWatchSession(_makeSession('h3'));
  });

  tearDown(() => p.dispose());

  test('renameSession sets customLabel', () async {
    p.renameSession(p.sessions.first.id, 'renamed');
    expect(p.sessions.first.customLabel, 'renamed');
  });

  test('renameSession with null clears label', () async {
    p.renameSession(p.sessions.first.id, 'x');
    p.renameSession(p.sessions.first.id, null);
    expect(p.sessions.first.customLabel, isNull);
  });

  test('setSessionColor sets colorTag', () async {
    p.setSessionColor(p.sessions.first.id, '#ef4444');
    expect(p.sessions.first.colorTag, '#ef4444');
  });

  test('setSessionColor with null clears color', () async {
    p.setSessionColor(p.sessions.first.id, '#ef4444');
    p.setSessionColor(p.sessions.first.id, null);
    expect(p.sessions.first.colorTag, isNull);
  });

  test('togglePin pins and moves session to front', () {
    final third = p.sessions[2];
    p.togglePin(third.id);
    expect(p.sessions.first.id, third.id);
    expect(p.sessions.first.isPinned, isTrue);
  });

  test('togglePin twice unpins and session leaves front', () {
    final third = p.sessions[2];
    p.togglePin(third.id);
    p.togglePin(third.id);
    expect(p.sessions.first.isPinned, isFalse);
  });

  test('reorderSession moves unpinned tab', () {
    // sessions: [h1, h2, h3], move h1 (index 0) to index 2
    final h1Id = p.sessions[0].id;
    p.reorderSession(0, 2);
    // After reorder: [h2, h1, h3]... actually Flutter's onReorder sends
    // newIndex=2 when moving to position after h2 (final position 1).
    // reorderSession applies newIndex -= 1 when newIndex > oldIndex.
    // 0 → newIndex 2 → adjusted 1. Result: [h2, h1, h3]
    expect(p.sessions[1].id, h1Id);
  });

  test('reorderSession: unpinned tab cannot be dragged into pinned zone', () {
    // Pin h1 (index 0).
    p.togglePin(p.sessions[0].id);
    // sessions: [h1(pinned), h2, h3]
    // Try to drag h2 (index 1) to index 0 (pinned zone).
    p.reorderSession(1, 0);
    // Should be clamped — h2 stays at index 1 (first unpinned slot).
    expect(p.sessions[0].isPinned, isTrue);
    expect(p.sessions[1].isPinned, isFalse);
  });

  test('reorderSession: pinned tab cannot be dragged into unpinned zone', () {
    p.togglePin(p.sessions[0].id);
    // sessions: [h1(pinned), h2, h3]
    // Try to drag h1 (index 0) to index 3 (past unpinned zone).
    final h1Id = p.sessions[0].id;
    p.reorderSession(0, 3);
    // Should be clamped — h1 stays at index 0 (only pinned slot).
    expect(p.sessions[0].id, h1Id);
    expect(p.sessions[0].isPinned, isTrue);
  });
});
```

- [ ] **Step 2: Run tests — expect compile errors**

```bash
cd app && flutter test test/providers/session_provider_test.dart
```

Expected: compile errors for `renameSession`, `setSessionColor`, `togglePin`, `reorderSession`.

- [ ] **Step 3: Implement the four methods in SessionProvider**

Add these methods to `app/lib/providers/session_provider.dart` (before the closing `}`):

```dart
void renameSession(String sessionId, String? label) {
  final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
  if (session == null) return;
  session.customLabel = label;
  _tabMetadata.saveMetadata(session.host.id,
      label: label, color: session.colorTag, pinned: session.isPinned);
  _safeNotify();
}

void setSessionColor(String sessionId, String? colorHex) {
  final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
  if (session == null) return;
  session.colorTag = colorHex;
  _tabMetadata.saveMetadata(session.host.id,
      label: session.customLabel, color: colorHex, pinned: session.isPinned);
  _safeNotify();
}

void togglePin(String sessionId) {
  final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
  if (session == null) return;
  session.isPinned = !session.isPinned;
  _sortSessions();
  _tabMetadata.saveMetadata(session.host.id,
      label: session.customLabel, color: session.colorTag, pinned: session.isPinned);
  _safeNotify();
}

void reorderSession(int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= _sessions.length) return;
  if (newIndex > oldIndex) newIndex -= 1;
  final session = _sessions[oldIndex];
  final pinnedCount = _sessions.where((s) => s.isPinned).length;
  if (session.isPinned) {
    newIndex = newIndex.clamp(0, (pinnedCount - 1).clamp(0, _sessions.length - 1));
  } else {
    newIndex = newIndex.clamp(pinnedCount, _sessions.length - 1);
  }
  if (newIndex == oldIndex) {
    _safeNotify();
    return;
  }
  _sessions.removeAt(oldIndex);
  _sessions.insert(newIndex, session);
  _safeNotify();
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/providers/session_provider_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Run full test suite to check no regressions**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_test.dart
git commit -m "feat(tabs): add renameSession, setSessionColor, togglePin, reorderSession to SessionProvider"
```

---

## Task 5: UI — _SessionTab visual updates (color dot, pin icon, hide close button)

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Update `_SessionTabState.build` to add color dot, pin icon, and hide close button when pinned**

In `app/lib/screens/main_screen.dart`, find `_SessionTabState.build` (around line 1110). Replace the content of the `Row` children inside `_SessionTab`:

Find this block (the children list inside the innermost `Row`):

```dart
children: [
  // Red recording indicator
  Consumer<RecordingProvider>(
    builder: (context, rec, _) => rec.isRecording(widget.session.id)
        ? Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 5),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          )
        : const SizedBox.shrink(),
  ),
  // X close button (left, per image)
  GestureDetector(
    onTap: () => widget.provider.closeSession(widget.session.id),
    child: Icon(
      Icons.close,
      size: 11,
      color: _hovered || widget.isActive ? const Color(0xFF888888) : const Color(0xFF444444),
    ),
  ),
  const SizedBox(width: 8),
  // Host label
  Text(
    widget.session.host.label,
    style: TextStyle(
      color: labelColor,
      fontSize: 12,
      fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
    ),
  ),
  const SizedBox(width: 8),
  // Terminal icon (right, per image)
  Icon(
    Icons.monitor_outlined,
    size: 13,
    color: widget.isActive ? AppColors.accent : const Color(0xFF555555),
  ),
],
```

Replace with:

```dart
children: [
  // Red recording indicator
  Consumer<RecordingProvider>(
    builder: (context, rec, _) => rec.isRecording(widget.session.id)
        ? Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 5),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          )
        : const SizedBox.shrink(),
  ),
  // Color dot (shown when colorTag is set)
  if (widget.session.colorTag != null) ...[
    Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        color: _hexColor(widget.session.colorTag!),
        shape: BoxShape.circle,
      ),
    ),
  ],
  // X close button — hidden when pinned
  if (!widget.session.isPinned)
    GestureDetector(
      onTap: () => widget.provider.closeSession(widget.session.id),
      child: Icon(
        Icons.close,
        size: 11,
        color: _hovered || widget.isActive ? const Color(0xFF888888) : const Color(0xFF444444),
      ),
    ),
  const SizedBox(width: 8),
  // Host label
  Text(
    widget.session.title,
    style: TextStyle(
      color: labelColor,
      fontSize: 12,
      fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
    ),
  ),
  const SizedBox(width: 8),
  // Pin icon (shown when pinned)
  if (widget.session.isPinned)
    const Padding(
      padding: EdgeInsets.only(right: 4),
      child: Icon(Icons.push_pin, size: 11, color: Color(0xFF888888)),
    ),
  // Terminal icon (right)
  Icon(
    Icons.monitor_outlined,
    size: 13,
    color: widget.isActive ? AppColors.accent : const Color(0xFF555555),
  ),
],
```

- [ ] **Step 2: Add `_hexColor` helper**

Add this private function at the bottom of the file (after the last class), or as a top-level function:

```dart
Color _hexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
```

Also add `import 'package:flutter/material.dart';` if not already present (it is — no change needed).

- [ ] **Step 3: Change label source from `host.label` to `session.title`**

The edit above already uses `widget.session.title` — verify the old `widget.session.host.label` reference is gone from `_SessionTabState.build`.

- [ ] **Step 4: Analyze and run**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
cd app && flutter run -d macos
```

Open a session and verify:
- Tab shows `user@host` (no custom label yet)
- No color dot (none set yet)
- Close button visible (not pinned)

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(tabs): show color dot, pin icon; hide close button when pinned"
```

---

## Task 6: UI — inline rename on double-tap

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add rename state to `_SessionTabState`**

`_SessionTab` is already a `StatefulWidget`. In `_SessionTabState`, add:

```dart
bool _isRenaming = false;
late TextEditingController _renameController;

@override
void initState() {
  super.initState();
  _renameController = TextEditingController();
}

@override
void dispose() {
  _renameController.dispose();
  super.dispose();
}
```

- [ ] **Step 2: Replace the label `Text` widget with a rename-aware widget**

In `_SessionTabState.build`, find:

```dart
// Host label
Text(
  widget.session.title,
  style: TextStyle(
    color: labelColor,
    fontSize: 12,
    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
  ),
),
```

Replace with:

```dart
// Host label — switches to Focus+TextField when renaming
if (_isRenaming)
  SizedBox(
    width: 100,
    height: 20,
    child: Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          setState(() => _isRenaming = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _renameController,
        autofocus: true,
        style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (value) {
          widget.provider.renameSession(
            widget.session.id,
            value.trim().isEmpty ? null : value.trim(),
          );
          setState(() => _isRenaming = false);
        },
        onEditingComplete: () {},
      ),
    ),
  )
else
  Text(
    widget.session.title,
    style: TextStyle(
      color: labelColor,
      fontSize: 12,
      fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
    ),
  ),
```

- [ ] **Step 3: Add `_startRename` helper**

Add to `_SessionTabState`:

```dart
void _startRename() {
  _renameController.text = widget.session.customLabel ?? widget.session.title;
  _renameController.selection = TextSelection(
    baseOffset: 0,
    extentOffset: _renameController.text.length,
  );
  setState(() => _isRenaming = true);
}
```

Add `import 'package:flutter/services.dart';` at the top of `main_screen.dart` if not present. Check: `grep -n "flutter/services" app/lib/screens/main_screen.dart` — add if missing.

- [ ] **Step 4: Add double-tap gesture**

In `_SessionTabState.build`, the outermost gesture is `GestureDetector(onTap: ...)`. Replace with:

```dart
GestureDetector(
  onTap: () {
    widget.provider.setActive(widget.session.id);
    widget.onTap();
  },
  onDoubleTap: _startRename,
  child: Container( /* existing */ ),
)
```

- [ ] **Step 5: Analyze and run**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
cd app && flutter run -d macos
```

Double-click a tab → label becomes a text field, type new name, Enter → tab shows new name. Escape → cancels.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(tabs): add inline rename on double-tap"
```

---

## Task 7: UI — right-click context menu with color submenu

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add `_showTabContextMenu` method to `_SessionTabState`**

Add this method to `_SessionTabState`:

```dart
static const _kTabColors = [
  ('Red',    '#ef4444'),
  ('Orange', '#f97316'),
  ('Yellow', '#eab308'),
  ('Green',  '#22c55e'),
  ('Teal',   '#14b8a6'),
  ('Blue',   '#3b82f6'),
  ('Purple', '#a855f7'),
  ('Pink',   '#ec4899'),
];

Future<void> _showTabContextMenu(BuildContext context, Offset globalPos) async {
  final session = widget.session;
  final provider = widget.provider;

  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
    ),
    color: const Color(0xFF1E1E1E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    items: [
      PopupMenuItem(
        value: 'rename',
        child: const Row(children: [
          Icon(Icons.edit_outlined, size: 14, color: Color(0xFFAAAAAA)),
          SizedBox(width: 8),
          Text('Rename', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
        ]),
      ),
      PopupMenuItem(
        value: 'pin',
        child: Row(children: [
          Icon(
            session.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            size: 14,
            color: const Color(0xFFAAAAAA),
          ),
          const SizedBox(width: 8),
          Text(
            session.isPinned ? 'Unpin' : 'Pin',
            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
          ),
        ]),
      ),
      PopupMenuItem(
        value: 'color',
        child: const Row(children: [
          Icon(Icons.circle_outlined, size: 14, color: Color(0xFFAAAAAA)),
          SizedBox(width: 8),
          Text('Color tag', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          Spacer(),
          Icon(Icons.chevron_right, size: 14, color: Color(0xFF666666)),
        ]),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'close',
        child: const Row(children: [
          Icon(Icons.close, size: 14, color: Color(0xFF888888)),
          SizedBox(width: 8),
          Text('Close', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
        ]),
      ),
    ],
  );

  if (!context.mounted) return;

  switch (result) {
    case 'rename':
      _startRename();
    case 'pin':
      provider.togglePin(session.id);
    case 'color':
      await _showColorSubmenu(context, globalPos);
    case 'close':
      provider.closeSession(session.id);
  }
}

Future<void> _showColorSubmenu(BuildContext context, Offset globalPos) async {
  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPos.dx + 160, globalPos.dy + 60,
      globalPos.dx + 161, globalPos.dy + 61,
    ),
    color: const Color(0xFF1E1E1E),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    items: [
      PopupMenuItem(
        value: 'none',
        child: const Row(children: [
          SizedBox(
            width: 14, height: 14,
            child: Icon(Icons.block, size: 12, color: Color(0xFF666666)),
          ),
          SizedBox(width: 8),
          Text('None', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
        ]),
      ),
      ..._kTabColors.map((c) => PopupMenuItem(
        value: c.$2,
        child: Row(children: [
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: _hexColor(c.$2),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(c.$1, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
        ]),
      )),
    ],
  );

  if (result != null) {
    widget.provider.setSessionColor(
      widget.session.id,
      result == 'none' ? null : result,
    );
  }
}
```

- [ ] **Step 2: Wire `onSecondaryTapUp` to show the context menu**

In `_SessionTabState.build`, the outermost `GestureDetector` has `onTap` and `onDoubleTap`. Add `onSecondaryTapUp`:

```dart
GestureDetector(
  onTap: () {
    widget.provider.setActive(widget.session.id);
    widget.onTap();
  },
  onDoubleTap: _startRename,
  onSecondaryTapUp: (details) =>
      _showTabContextMenu(context, details.globalPosition),
  child: Container( /* existing */ ),
)
```

- [ ] **Step 3: Analyze and run**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
cd app && flutter run -d macos
```

Right-click a tab → context menu appears. Select Rename → inline rename activates. Select Pin → tab moves to front, pin icon appears, close button hides. Select Color tag → color submenu → pick a color → dot appears on tab. Select Close → tab closes.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(tabs): add right-click context menu with rename, pin, color tag, close"
```

---

## Task 8: UI — drag reorder with ReorderableListView

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Replace `ListView` with `ReorderableListView` in `_TopTabBar`**

In `app/lib/screens/main_screen.dart`, find the `Expanded` child inside `_TopTabBar.build` (around line 1018):

```dart
Expanded(
  child: ListView(
    scrollDirection: Axis.horizontal,
    children: sessions
        .map((s) => _SessionTab(
              session: s,
              isActive: s.id == active?.id && viewingTerminal,
              provider: provider,
              onTap: () => onSessionTap(s.id),
            ))
        .toList(),
  ),
),
```

Replace with:

```dart
Expanded(
  child: ReorderableListView.builder(
    scrollDirection: Axis.horizontal,
    buildDefaultDragHandles: false,
    itemCount: sessions.length,
    onReorder: provider.reorderSession,
    itemBuilder: (context, index) {
      final s = sessions[index];
      return ReorderableDragStartListener(
        key: ValueKey(s.id),
        index: index,
        child: _SessionTab(
          session: s,
          isActive: s.id == active?.id && viewingTerminal,
          provider: provider,
          onTap: () => onSessionTap(s.id),
        ),
      );
    },
  ),
),
```

- [ ] **Step 2: Analyze and run**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
cd app && flutter run -d macos
```

Open 3+ sessions. Click-and-drag a tab left or right — it should reorder. Verify:
- Pinned tab cannot be dragged past the pinned/unpinned boundary.
- Order persists after app restart (WorkspaceService auto-saves via existing `_onSessionsChangedForSave` listener).

- [ ] **Step 3: Run full test suite**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(tabs): add drag reorder via ReorderableListView"
```

---

## Task 9: Final integration check

- [ ] **Step 1: Full analyze**

```bash
cd app && flutter analyze
```

Expected: No errors, no warnings introduced by this feature.

- [ ] **Step 2: Full test suite**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [ ] **Step 3: Manual regression checklist**

Run `cd app && flutter run -d macos` and verify:

- [ ] Rename: double-click tab → rename inline → Enter persists label → reconnect same host → label restored
- [ ] Rename: Escape cancels without changing label
- [ ] Color: right-click → Color tag → pick Red → red dot appears → reconnect → dot restored
- [ ] Color: right-click → Color tag → None → dot removed
- [ ] Pin: right-click → Pin → tab moves to front, pin icon shown, close button hidden
- [ ] Pin: right-click → Unpin → tab moves back, pin icon gone, close button returns
- [ ] Drag: drag tabs to reorder → order persists after app restart
- [ ] Drag: pinned tab cannot cross into unpinned zone
- [ ] Context menu Close works normally for unpinned tabs
- [ ] Existing features unaffected: split view, broadcast, recording indicator, watch sessions
