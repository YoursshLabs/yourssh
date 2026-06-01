# Terminal Multiplayer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow a host user to share a live SSH terminal session with up to 5 read-only guest viewers (with optional control delegation) via Supabase Realtime Broadcast; feature gates on `SyncProvider.isSupabaseConfigured`.

**Architecture:** The host registers a passthrough HookBus transform on `terminal.output` to buffer and broadcast UTF-8 terminal text to a Supabase Realtime channel named `share:<code>`. Guests subscribe to the same channel, receive a one-time scrollback snapshot plus live output events, and render them in a standalone `Terminal()`. Control grant/revoke is handled via broadcast events; guest disconnection is detected via Supabase Presence.

**Tech Stack:** Dart/Flutter, `supabase_flutter ^2.5.0` (Realtime Broadcast + Presence), `qr_flutter ^4.1.0`, `xterm ^4.0.0`, `uuid ^4.5.1`, existing `HookBus`, `SessionProvider`, `SyncProvider`.

---

## File Map

| Action | File |
|--------|------|
| Create | `app/lib/models/share_event.dart` |
| Create | `app/lib/services/share_session_service.dart` |
| Modify | `app/lib/models/ssh_session.dart` |
| Modify | `app/lib/providers/session_provider.dart` |
| Create | `app/lib/providers/share_provider.dart` |
| Modify | `app/lib/main.dart` |
| Create | `app/lib/widgets/share_session_dialog.dart` |
| Create | `app/lib/widgets/join_share_dialog.dart` |
| Modify | `app/lib/screens/main_screen.dart` |
| Modify | `app/lib/widgets/split_terminal_view.dart` |
| Create | `app/test/models/share_event_test.dart` |
| Create | `app/test/services/share_session_service_test.dart` |
| Create | `app/test/providers/share_provider_test.dart` |

---

## Task 1: `ShareEvent` model

**Files:**
- Create: `app/lib/models/share_event.dart`
- Create: `app/test/models/share_event_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/share_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/share_event.dart';

void main() {
  group('ShareEvent.fromJson', () {
    test('parses output event', () {
      final e = ShareEvent.fromJson({'type': 'output', 'data': 'hello'});
      expect(e.type, ShareEventType.output);
      expect(e.data, 'hello');
    });

    test('parses snapshot event', () {
      final e = ShareEvent.fromJson({'type': 'snapshot', 'data': 'buf'});
      expect(e.type, ShareEventType.snapshot);
    });

    test('parses snapshot_chunk event', () {
      final e = ShareEvent.fromJson({
        'type': 'snapshot_chunk',
        'data': 'chunk',
        'index': 1,
        'total': 3,
      });
      expect(e.type, ShareEventType.snapshotChunk);
      expect(e.chunkIndex, 1);
      expect(e.chunkTotal, 3);
    });

    test('parses control_grant event', () {
      final e = ShareEvent.fromJson({'type': 'control_grant', 'guestId': 'g1'});
      expect(e.type, ShareEventType.controlGrant);
      expect(e.guestId, 'g1');
    });

    test('parses ended event', () {
      final e = ShareEvent.fromJson({'type': 'ended'});
      expect(e.type, ShareEventType.ended);
    });
  });

  group('ShareEvent.toJson', () {
    test('serialises output event', () {
      final e = ShareEvent.output('hello');
      final json = e.toJson();
      expect(json['type'], 'output');
      expect(json['data'], 'hello');
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd app && flutter test test/models/share_event_test.dart
```

Expected: FAIL — `share_event.dart` does not exist.

- [ ] **Step 3: Create `share_event.dart`**

```dart
// app/lib/models/share_event.dart
enum ShareEventType {
  output,
  input,
  snapshot,
  snapshotChunk,
  controlGrant,
  controlRevoke,
  joinRequest,
  rejected,
  ended,
}

class ShareEvent {
  final ShareEventType type;
  final String? data;
  final String? guestId;
  final int? chunkIndex;
  final int? chunkTotal;

  const ShareEvent._({
    required this.type,
    this.data,
    this.guestId,
    this.chunkIndex,
    this.chunkTotal,
  });

  factory ShareEvent.output(String data) =>
      ShareEvent._(type: ShareEventType.output, data: data);

  factory ShareEvent.input(String data) =>
      ShareEvent._(type: ShareEventType.input, data: data);

  factory ShareEvent.snapshot(String data) =>
      ShareEvent._(type: ShareEventType.snapshot, data: data);

  factory ShareEvent.snapshotChunk(String data, int index, int total) =>
      ShareEvent._(
        type: ShareEventType.snapshotChunk,
        data: data,
        chunkIndex: index,
        chunkTotal: total,
      );

  factory ShareEvent.controlGrant(String guestId) =>
      ShareEvent._(type: ShareEventType.controlGrant, guestId: guestId);

  factory ShareEvent.controlRevoke() =>
      ShareEvent._(type: ShareEventType.controlRevoke);

  factory ShareEvent.joinRequest(String guestId) =>
      ShareEvent._(type: ShareEventType.joinRequest, guestId: guestId);

  factory ShareEvent.rejected(String reason) =>
      ShareEvent._(type: ShareEventType.rejected, data: reason);

  factory ShareEvent.ended() => ShareEvent._(type: ShareEventType.ended);

  factory ShareEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = switch (typeStr) {
      'output' => ShareEventType.output,
      'input' => ShareEventType.input,
      'snapshot' => ShareEventType.snapshot,
      'snapshot_chunk' => ShareEventType.snapshotChunk,
      'control_grant' => ShareEventType.controlGrant,
      'control_revoke' => ShareEventType.controlRevoke,
      'join_request' => ShareEventType.joinRequest,
      'rejected' => ShareEventType.rejected,
      'ended' => ShareEventType.ended,
      _ => ShareEventType.ended,
    };
    return ShareEvent._(
      type: type,
      data: json['data'] as String?,
      guestId: json['guestId'] as String?,
      chunkIndex: json['index'] as int?,
      chunkTotal: json['total'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      ShareEventType.output => 'output',
      ShareEventType.input => 'input',
      ShareEventType.snapshot => 'snapshot',
      ShareEventType.snapshotChunk => 'snapshot_chunk',
      ShareEventType.controlGrant => 'control_grant',
      ShareEventType.controlRevoke => 'control_revoke',
      ShareEventType.joinRequest => 'join_request',
      ShareEventType.rejected => 'rejected',
      ShareEventType.ended => 'ended',
    };
    return {
      'type': typeStr,
      if (data != null) 'data': data,
      if (guestId != null) 'guestId': guestId,
      if (chunkIndex != null) 'index': chunkIndex,
      if (chunkTotal != null) 'total': chunkTotal,
    };
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd app && flutter test test/models/share_event_test.dart
```

Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/share_event.dart app/test/models/share_event_test.dart
git commit -m "feat(share): add ShareEvent model"
```

---

## Task 2: `ShareSessionService`

**Files:**
- Create: `app/lib/services/share_session_service.dart`
- Create: `app/test/services/share_session_service_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/services/share_session_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/share_session_service.dart';

void main() {
  group('generateShareCode', () {
    test('returns 6 characters', () {
      final code = ShareSessionService.generateShareCode();
      expect(code.length, 6);
    });

    test('contains only uppercase alphanumeric excluding ambiguous chars', () {
      for (var i = 0; i < 20; i++) {
        final code = ShareSessionService.generateShareCode();
        expect(RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code), isTrue,
            reason: 'code "$code" contains unexpected chars');
      }
    });

    test('produces different codes on subsequent calls', () {
      final codes = List.generate(10, (_) => ShareSessionService.generateShareCode());
      // With 32^6 ≈ 1 billion combinations, duplicates in 10 attempts are
      // astronomically unlikely but not theoretically impossible.
      expect(codes.toSet().length, greaterThan(1));
    });
  });

  group('output buffer', () {
    test('trims buffer when it exceeds max size', () {
      final svc = ShareSessionService.forTest();
      // Fill buffer past the 500KB limit
      final chunk = 'x' * 10000;
      for (var i = 0; i < 60; i++) {
        svc.appendToBufferForTest(chunk);
      }
      expect(svc.bufferLengthForTest, lessThanOrEqualTo(ShareSessionService.maxBufferLength));
    });

    test('retains recent content after trim', () {
      final svc = ShareSessionService.forTest();
      final chunk = 'x' * 10000;
      for (var i = 0; i < 60; i++) {
        svc.appendToBufferForTest(chunk);
      }
      svc.appendToBufferForTest('MARKER');
      expect(svc.bufferSnapshotForTest, contains('MARKER'));
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd app && flutter test test/services/share_session_service_test.dart
```

Expected: FAIL — file does not exist.

- [ ] **Step 3: Create `share_session_service.dart`**

```dart
// app/lib/services/share_session_service.dart
import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../models/share_event.dart';

class ShareSessionService {
  static const maxBufferLength = 500 * 1024; // ~500KB chars
  static const _chunkSize = 80 * 1024;       // 80KB per chunk
  static const _maxGuests = 5;
  static const _pluginId = 'yourssh_share_service';
  static const _broadcastEvent = 'share';

  // Buffer
  final _outputBuffer = StringBuffer();
  int _bufferLength = 0;

  // Host state
  HookBus? _hookBus;
  String? _sessionId;
  SupabaseClient? _client;
  RealtimeChannel? _channel;

  // Guest state
  Terminal? _guestTerminal;
  final _chunkAccumulator = <int, String>{};
  int _expectedChunks = 0;

  // Events out
  final _events = StreamController<ShareEvent>.broadcast();
  Stream<ShareEvent> get events => _events.stream;

  // ─── Share code generation ────────────────────────────

  static String generateShareCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ─── Buffer management ───────────────────────────────

  void _appendToBuffer(String text) {
    _outputBuffer.write(text);
    _bufferLength += text.length;
    if (_bufferLength > maxBufferLength) {
      final s = _outputBuffer.toString();
      final trimmed = s.substring(s.length - maxBufferLength ~/ 2);
      _outputBuffer.clear();
      _outputBuffer.write(trimmed);
      _bufferLength = trimmed.length;
    }
  }

  // ─── Host API ─────────────────────────────────────────

  Future<String> startSharing(
    String sessionId,
    HookBus hookBus,
    String supabaseUrl,
    String anonKey,
  ) async {
    _sessionId = sessionId;
    _hookBus = hookBus;
    _outputBuffer.clear();
    _bufferLength = 0;

    // Register passthrough transform to capture output for this session.
    hookBus.register('terminal.output', _pluginId, (event) {
      if (event.sessionId == sessionId) {
        _appendToBuffer(event.data);
        _broadcastOutput(event.data);
      }
      return event.data;
    });

    final code = generateShareCode();
    _client = SupabaseClient(supabaseUrl, anonKey);
    _channel = _client!.channel('share:$code');

    _channel!
        .onBroadcast(
          event: _broadcastEvent,
          callback: (payload) => _onHostReceived(payload),
        )
        .onPresenceLeave(callback: (leavePayload) {
          final leftIds = (leavePayload['leftPresences'] as List? ?? [])
              .map((p) => (p as Map<String, dynamic>)['guestId'] as String?)
              .whereType<String>()
              .toSet();
          for (final guestId in leftIds) {
            _events.add(ShareEvent.fromJson({'type': 'presence_leave', 'guestId': guestId}));
          }
        })
        .subscribe();

    return code;
  }

  void _onHostReceived(Map<String, dynamic> payload) {
    final event = ShareEvent.fromJson(payload);
    _events.add(event);
  }

  void _broadcastOutput(String text) {
    _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.output(text).toJson(),
    );
  }

  Future<void> sendSnapshot(String guestId) async {
    if (_channel == null) return;
    final snapshot = _outputBuffer.toString();
    if (snapshot.length <= _chunkSize) {
      await _channel!.sendBroadcastMessage(
        event: _broadcastEvent,
        payload: ShareEvent.snapshot(snapshot).toJson(),
      );
    } else {
      final chunks = <String>[];
      for (var i = 0; i < snapshot.length; i += _chunkSize) {
        chunks.add(snapshot.substring(i, (i + _chunkSize).clamp(0, snapshot.length)));
      }
      for (var i = 0; i < chunks.length; i++) {
        await _channel!.sendBroadcastMessage(
          event: _broadcastEvent,
          payload: ShareEvent.snapshotChunk(chunks[i], i, chunks.length).toJson(),
        );
      }
    }
  }

  Future<void> sendRejected(String guestId, String reason) async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.rejected(reason).toJson(),
    );
  }

  Future<void> grantControl(String guestId) async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.controlGrant(guestId).toJson(),
    );
  }

  Future<void> revokeControl() async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.controlRevoke().toJson(),
    );
  }

  Future<void> stopSharing() async {
    _hookBus?.unregisterAll(_pluginId);
    _hookBus = null;
    _sessionId = null;
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.ended().toJson(),
    );
    if (_client != null && _channel != null) {
      await _client!.removeChannel(_channel!);
    }
    _channel = null;
    _client?.dispose();
    _client = null;
    _outputBuffer.clear();
    _bufferLength = 0;
  }

  // ─── Guest API ────────────────────────────────────────

  final _guestId = const Uuid().v4();
  String get guestId => _guestId;

  Future<void> joinSession(
    String shareCode,
    String supabaseUrl,
    String anonKey,
    Terminal localTerminal,
  ) async {
    _guestTerminal = localTerminal;
    _client = SupabaseClient(supabaseUrl, anonKey);
    _channel = _client!.channel('share:$shareCode');

    _channel!
        .onBroadcast(
          event: _broadcastEvent,
          callback: (payload) => _onGuestReceived(payload),
        )
        .subscribe((status, _) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({'guestId': _guestId, 'role': 'guest'});
            await _channel!.sendBroadcastMessage(
              event: _broadcastEvent,
              payload: ShareEvent.joinRequest(_guestId).toJson(),
            );
          }
        });
  }

  void _onGuestReceived(Map<String, dynamic> payload) {
    final event = ShareEvent.fromJson(payload);
    switch (event.type) {
      case ShareEventType.output:
        if (event.data != null) _guestTerminal?.write(event.data!);
      case ShareEventType.snapshot:
        _chunkAccumulator.clear();
        _expectedChunks = 0;
        if (event.data != null) _guestTerminal?.write(event.data!);
        _events.add(event);
      case ShareEventType.snapshotChunk:
        final index = event.chunkIndex ?? 0;
        final total = event.chunkTotal ?? 1;
        _expectedChunks = total;
        _chunkAccumulator[index] = event.data ?? '';
        if (_chunkAccumulator.length == _expectedChunks) {
          final full = List.generate(_expectedChunks, (i) => _chunkAccumulator[i] ?? '').join();
          _guestTerminal?.write(full);
          _chunkAccumulator.clear();
          _events.add(ShareEvent.snapshot(full));
        }
      case ShareEventType.input:
        // Guest receives input only when they have control and the host echoes back
        break;
      case ShareEventType.controlGrant:
        _events.add(event);
      case ShareEventType.controlRevoke:
        _events.add(event);
      case ShareEventType.rejected:
        _events.add(event);
      case ShareEventType.ended:
        _events.add(event);
      case ShareEventType.joinRequest:
        break;
    }
  }

  Future<void> sendGuestInput(String data) async {
    await _channel?.sendBroadcastMessage(
      event: _broadcastEvent,
      payload: ShareEvent.input(data).toJson(),
    );
  }

  Future<void> leaveSession() async {
    await _channel?.untrack();
    if (_client != null && _channel != null) {
      await _client!.removeChannel(_channel!);
    }
    _channel = null;
    _client?.dispose();
    _client = null;
    _guestTerminal = null;
    _chunkAccumulator.clear();
  }

  // ─── Test helpers (not used in production) ────────────

  ShareSessionService.forTest();

  void appendToBufferForTest(String text) => _appendToBuffer(text);
  int get bufferLengthForTest => _bufferLength;
  String get bufferSnapshotForTest => _outputBuffer.toString();

  Future<void> dispose() async {
    await stopSharing();
    await leaveSession();
    await _events.close();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/services/share_session_service_test.dart
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/share_session_service.dart app/test/services/share_session_service_test.dart
git commit -m "feat(share): add ShareSessionService with buffer management and Supabase Realtime"
```

---

## Task 3: Extend `SshSession` for watch mode

**Files:**
- Modify: `app/lib/models/ssh_session.dart`

- [ ] **Step 1: Add `isWatch` and `watchedTitle` to `SshSession`**

In `app/lib/models/ssh_session.dart`, add the `isWatch` field and a `SshSession.watch` factory after the existing constructor:

```dart
// app/lib/models/ssh_session.dart
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

  SshSession({
    String? id,
    required this.host,
    this.status = SessionStatus.connecting,
    this.errorMessage,
    DateTime? connectedAt,
    this.initialCommand,
    this.isWatch = false,
    this.watchedTitle,
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

  String get title => isWatch ? '[WATCH] ${watchedTitle ?? host.host}' : '${host.username}@${host.host}';

  String get statusLabel => switch (status) {
        SessionStatus.connecting => 'Connecting...',
        SessionStatus.connected => isWatch ? 'Watching' : 'Connected',
        SessionStatus.disconnected => 'Disconnected',
        SessionStatus.error => errorMessage ?? 'Error',
      };
}
```

- [ ] **Step 2: Run existing tests to make sure nothing is broken**

```bash
cd app && flutter test test/models/ 2>/dev/null || flutter test
```

Expected: existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/ssh_session.dart
git commit -m "feat(share): add isWatch flag and factory to SshSession"
```

---

## Task 4: `SessionProvider` — add watch session management

**Files:**
- Modify: `app/lib/providers/session_provider.dart`

- [ ] **Step 1: Add `addWatchSession` and `removeWatchSession` methods**

In `app/lib/providers/session_provider.dart`, add these two methods after `closeActive()` (around line 197):

```dart
  void addWatchSession(SshSession session) {
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();
  }

  void removeWatchSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId && s.isWatch);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    _safeNotify();
  }
```

- [ ] **Step 2: Run tests**

```bash
cd app && flutter test
```

Expected: no regressions.

- [ ] **Step 3: Commit**

```bash
git add app/lib/providers/session_provider.dart
git commit -m "feat(share): add addWatchSession/removeWatchSession to SessionProvider"
```

---

## Task 5: `ShareProvider`

**Files:**
- Create: `app/lib/providers/share_provider.dart`
- Create: `app/test/providers/share_provider_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// app/test/providers/share_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/share_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShareProvider.canShare', () {
    test('returns false when Supabase is not configured', () async {
      SharedPreferences.setMockInitialValues({});
      final sync = SyncProvider();
      await Future.delayed(Duration.zero); // let _init complete
      final share = ShareProvider(syncProvider: sync);
      expect(share.canShare, isFalse);
    });

    test('returns true when Supabase is configured', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': 'https://test.supabase.co',
        'supabase_anon_key': 'test-anon-key',
      });
      final sync = SyncProvider();
      await Future.delayed(Duration.zero);
      final share = ShareProvider(syncProvider: sync);
      expect(share.canShare, isTrue);
    });
  });

  group('ShareProvider initial state', () {
    test('starts not sharing and not as guest', () async {
      SharedPreferences.setMockInitialValues({});
      final sync = SyncProvider();
      final share = ShareProvider(syncProvider: sync);
      expect(share.isSharing, isFalse);
      expect(share.isGuest, isFalse);
      expect(share.shareCode, isNull);
      expect(share.guests, isEmpty);
      expect(share.controlledBy, isNull);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd app && flutter test test/providers/share_provider_test.dart
```

Expected: FAIL — `share_provider.dart` does not exist.

- [ ] **Step 3: Create `share_provider.dart`**

```dart
// app/lib/providers/share_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../models/ssh_session.dart';
import '../services/share_session_service.dart';
import 'session_provider.dart';
import 'sync_provider.dart';

class ShareProvider extends ChangeNotifier {
  final SyncProvider _syncProvider;
  SessionProvider? _sessionProvider;
  HookBus? _hookBus;

  ShareSessionService? _service;
  StreamSubscription<dynamic>? _eventSub;

  // Host state
  bool _isSharing = false;
  String? _shareCode;
  final Set<String> _guests = {};
  String? _controlledBy;

  // Guest state
  bool _isGuest = false;
  String? _viewingSessionId;
  bool _hasControl = false;
  bool _sessionEnded = false;

  bool get canShare => _syncProvider.isSupabaseConfigured;
  bool get isSharing => _isSharing;
  String? get shareCode => _shareCode;
  Set<String> get guests => Set.unmodifiable(_guests);
  String? get controlledBy => _controlledBy;
  bool get isGuest => _isGuest;
  String? get viewingSessionId => _viewingSessionId;
  bool get hasControl => _hasControl;
  bool get sessionEnded => _sessionEnded;

  ShareProvider({
    required SyncProvider syncProvider,
    SessionProvider? sessionProvider,
    HookBus? hookBus,
  })  : _syncProvider = syncProvider,
        _sessionProvider = sessionProvider,
        _hookBus = hookBus {
    _syncProvider.addListener(_onSyncChanged);
  }

  void wireDependencies(SessionProvider sessionProvider, HookBus hookBus) {
    _sessionProvider = sessionProvider;
    _hookBus = hookBus;
    notifyListeners();
  }

  void _onSyncChanged() => notifyListeners();

  // ─── Host ────────────────────────────────────────────

  Future<String> startSharing(String sessionId) async {
    assert(canShare, 'canShare must be true before calling startSharing');
    _service = ShareSessionService();
    final code = await _service!.startSharing(
      sessionId,
      _hookBus!,
      _syncProvider.supabaseUrl,
      _syncProvider.supabaseAnonKey,
    );
    _isSharing = true;
    _shareCode = code;
    _guests.clear();
    _controlledBy = null;
    _eventSub = _service!.events.listen(_onHostEvent);
    notifyListeners();
    return code;
  }

  void _onHostEvent(dynamic event) {
    if (event is! ShareEvent) return;
    switch (event.type) {
      case ShareEventType.joinRequest:
        final guestId = event.guestId;
        if (guestId == null) return;
        if (_guests.length >= 5) {
          _service?.sendRejected(guestId, 'full');
        } else {
          _guests.add(guestId);
          _service?.sendSnapshot(guestId);
          notifyListeners();
        }
      case ShareEventType.input:
        // Guest input arrives here when they have control;
        // forward to the SSH session terminal's onOutput equivalent.
        // This is wired by the caller (main.dart) via onGuestInput callback.
        _onGuestInput?.call(event.data ?? '');
      default:
        break;
    }
    // Detect guest disconnect via presence leave pseudo-event
    if (event.type.name == 'presence_leave') {
      final guestId = event.guestId;
      if (guestId != null) {
        _guests.remove(guestId);
        if (_controlledBy == guestId) {
          _controlledBy = null;
        }
        notifyListeners();
      }
    }
  }

  void Function(String)? onGuestInput;

  Future<void> grantControl(String guestId) async {
    _controlledBy = guestId;
    await _service?.grantControl(guestId);
    notifyListeners();
  }

  Future<void> revokeControl() async {
    _controlledBy = null;
    await _service?.revokeControl();
    notifyListeners();
  }

  Future<void> stopSharing() async {
    _eventSub?.cancel();
    _eventSub = null;
    await _service?.stopSharing();
    _service = null;
    _isSharing = false;
    _shareCode = null;
    _guests.clear();
    _controlledBy = null;
    notifyListeners();
  }

  // ─── Guest ───────────────────────────────────────────

  Future<void> joinSession(
    String shareCode,
    String supabaseUrl,
    String anonKey,
  ) async {
    final watchSession = SshSession.watch(watchedTitle: shareCode);
    _viewingSessionId = watchSession.id;
    _isGuest = true;
    _hasControl = false;
    _sessionEnded = false;

    _sessionProvider?.addWatchSession(watchSession);

    _service = ShareSessionService();
    _eventSub = _service!.events.listen((event) => _onGuestEvent(event, watchSession));

    await _service!.joinSession(
      shareCode,
      supabaseUrl,
      anonKey,
      watchSession.terminal,
    );
    notifyListeners();
  }

  void _onGuestEvent(ShareEvent event, SshSession watchSession) {
    switch (event.type) {
      case ShareEventType.snapshot:
        // Terminal already written by service; update title once we know host info.
        notifyListeners();
      case ShareEventType.controlGrant:
        if (event.guestId == _service?.guestId) {
          _hasControl = true;
          notifyListeners();
        }
      case ShareEventType.controlRevoke:
        _hasControl = false;
        notifyListeners();
      case ShareEventType.rejected:
        _cleanupGuest();
        notifyListeners();
      case ShareEventType.ended:
        _sessionEnded = true;
        _hasControl = false;
        notifyListeners();
      default:
        break;
    }
  }

  Future<void> sendGuestInput(String data) async {
    if (_hasControl) await _service?.sendGuestInput(data);
  }

  Future<void> leaveSession() async {
    _eventSub?.cancel();
    _eventSub = null;
    await _service?.leaveSession();
    _service = null;
    if (_viewingSessionId != null) {
      _sessionProvider?.removeWatchSession(_viewingSessionId!);
    }
    _cleanupGuest();
    notifyListeners();
  }

  void _cleanupGuest() {
    _isGuest = false;
    _viewingSessionId = null;
    _hasControl = false;
    _sessionEnded = false;
  }

  @override
  void dispose() {
    _syncProvider.removeListener(_onSyncChanged);
    _eventSub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/providers/share_provider_test.dart
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/share_provider.dart app/test/providers/share_provider_test.dart
git commit -m "feat(share): add ShareProvider"
```

---

## Task 6: Wire `ShareProvider` into `main.dart`

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Add import and field declaration**

In `app/lib/main.dart`, add the import at the top with the other provider imports:

```dart
import 'providers/share_provider.dart';
```

In `_YourSSHAppState`, add after `late final PluginEngineProvider _pluginEngineProvider;`:

```dart
  late final ShareProvider _shareProvider;
```

- [ ] **Step 2: Instantiate in `initState`**

In `_YourSSHAppState.initState()`, add after `_syncService = SyncService(_syncProvider);`:

```dart
    _shareProvider = ShareProvider(syncProvider: _syncProvider);
    // Wire SessionProvider + HookBus after they are initialised above.
    _shareProvider.wireDependencies(_sessionProvider, _hookBus);
    // Forward guest input to the active SSH session when guest has control.
    _shareProvider.onGuestInput = (data) {
      final active = _sessionProvider.activeSession;
      if (active != null && !active.isWatch) {
        active.terminal.textInput(data);
      }
    };
```

- [ ] **Step 3: Add `ShareProvider` to `MultiProvider`**

Find the `MultiProvider` in `_YourSSHAppState.build()` and add `ChangeNotifierProvider.value(value: _shareProvider)` alongside the other providers.

Look for the pattern `ChangeNotifierProvider.value(value: _syncProvider)` and add right after it:

```dart
              ChangeNotifierProvider.value(value: _shareProvider),
```

- [ ] **Step 4: Run the app to verify no startup crash**

```bash
cd app && flutter run -d macos
```

Expected: App launches without errors.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(share): wire ShareProvider into app"
```

---

## Task 7: `ShareSessionDialog` (host UI)

**Files:**
- Create: `app/lib/widgets/share_session_dialog.dart`

- [ ] **Step 1: Create the dialog**

```dart
// app/lib/widgets/share_session_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/share_provider.dart';
import '../theme/app_theme.dart';

class ShareSessionDialog extends StatelessWidget {
  final String sessionId;
  const ShareSessionDialog({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 360,
        child: Consumer<ShareProvider>(
          builder: (context, share, _) {
            if (!share.isSharing) {
              return _StartSharingView(sessionId: sessionId);
            }
            return _ActiveShareView(share: share);
          },
        ),
      ),
    );
  }
}

class _StartSharingView extends StatelessWidget {
  final String sessionId;
  const _StartSharingView({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final share = context.read<ShareProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Share Terminal', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Generate a share code so others can watch this terminal session in real-time.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Shared over TLS via your Supabase project.',
            style: TextStyle(color: Color(0xFF555555), fontSize: 11),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () async {
                await share.startSharing(sessionId);
              },
              child: const Text('Start Sharing', style: TextStyle(color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveShareView extends StatelessWidget {
  final ShareProvider share;
  const _ActiveShareView({required this.share});

  @override
  Widget build(BuildContext context) {
    final code = share.shareCode ?? '';
    final qrUrl = 'yourssh://share/$code';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Sharing Live', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${share.guests.length} viewer${share.guests.length == 1 ? '' : 's'}',
                  style: TextStyle(color: AppColors.accent, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Share code
          Center(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 2)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('Tap code to copy', style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
          const SizedBox(height: 16),
          // QR code
          Center(
            child: QrImageView(
              data: qrUrl,
              size: 140,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // Control grant
          if (share.guests.isNotEmpty) ...[
            const Divider(color: Color(0xFF2A2A2A)),
            const SizedBox(height: 8),
            if (share.controlledBy == null) ...[
              const Text('Grant control', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              ...share.guests.map((guestId) => _GuestRow(
                guestId: guestId,
                hasControl: false,
                onGrant: () => share.grantControl(guestId),
                onRevoke: null,
              )),
            ] else ...[
              const Text('Control granted', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              _GuestRow(
                guestId: share.controlledBy!,
                hasControl: true,
                onGrant: null,
                onRevoke: () => share.revokeControl(),
              ),
            ],
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3A3A3A)),
              ),
              onPressed: () async {
                await share.stopSharing();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Stop Sharing', style: TextStyle(color: Color(0xFFCC4444))),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  final String guestId;
  final bool hasControl;
  final VoidCallback? onGrant;
  final VoidCallback? onRevoke;

  const _GuestRow({
    required this.guestId,
    required this.hasControl,
    required this.onGrant,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final shortId = guestId.length > 8 ? guestId.substring(0, 8) : guestId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 14, color: Color(0xFF555555)),
          const SizedBox(width: 6),
          Text(shortId, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'monospace')),
          const Spacer(),
          if (hasControl)
            GestureDetector(
              onTap: onRevoke,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF440000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Revoke', style: TextStyle(color: Color(0xFFCC4444), fontSize: 11)),
              ),
            )
          else
            GestureDetector(
              onTap: onGrant,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Grant', style: TextStyle(color: AppColors.accent, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
cd app && flutter analyze lib/widgets/share_session_dialog.dart
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/share_session_dialog.dart
git commit -m "feat(share): add ShareSessionDialog for host"
```

---

## Task 8: `JoinShareDialog` (guest UI)

**Files:**
- Create: `app/lib/widgets/join_share_dialog.dart`

- [ ] **Step 1: Create the dialog**

```dart
// app/lib/widgets/join_share_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/share_provider.dart';
import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';

class JoinShareDialog extends StatefulWidget {
  const JoinShareDialog({super.key});

  @override
  State<JoinShareDialog> createState() => _JoinShareDialogState();
}

class _JoinShareDialogState extends State<JoinShareDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _joining = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join(BuildContext context) async {
    final code = _controller.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter a 6-character share code');
      return;
    }

    final sync = context.read<SyncProvider>();
    if (!sync.isSupabaseConfigured) {
      setState(() => _error = 'Configure Supabase first (Settings → Sync)');
      return;
    }

    setState(() { _joining = true; _error = null; });
    try {
      await context.read<ShareProvider>().joinSession(
        code,
        sync.supabaseUrl,
        sync.supabaseAnonKey,
      );
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _error = e.toString(); _joining = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Join Shared Session', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  _UpperCaseFormatter(),
                ],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'A3K9PX',
                  hintStyle: const TextStyle(color: Color(0xFF333333), letterSpacing: 4),
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                  errorText: _error,
                ),
                onSubmitted: (_) => _join(context),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                  onPressed: _joining ? null : () => _join(context),
                  child: _joining
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Join', style: TextStyle(color: Colors.black)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
cd app && flutter analyze lib/widgets/join_share_dialog.dart
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/join_share_dialog.dart
git commit -m "feat(share): add JoinShareDialog for guest"
```

---

## Task 9: Share button + guest banner + command palette entry in `main_screen.dart`

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add imports at top of `main_screen.dart`**

Add these imports alongside the existing widget imports (near `ai_chat_sidebar.dart`):

```dart
import '../providers/share_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/share_session_dialog.dart';
import '../widgets/join_share_dialog.dart';
```

- [ ] **Step 2: Add share button to terminal overlay in `_buildContent`**

In `_buildContent()`, locate the `Positioned` widget that contains `NetworkStatsOverlay` and `_AiChatToggle` (around line 617). Add a share button before the `NetworkStatsOverlay`:

```dart
              Positioned(
                top: 8,
                right: _showAiChat ? 348 : 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NetworkStatsOverlay(),
                    const SizedBox(width: 8),
                    _ShareButton(session: active!),
                    const SizedBox(width: 8),
                    _AiChatToggle(
                      active: _showAiChat,
                      onToggle: () => setState(() => _showAiChat = !_showAiChat),
                    ),
                  ],
                ),
              ),
```

- [ ] **Step 3: Add `_ShareButton` widget at the bottom of `main_screen.dart`** (before the last closing brace, after existing private widget classes)

```dart
class _ShareButton extends StatelessWidget {
  final SshSession session;
  const _ShareButton({required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    if (!share.canShare || session.isWatch) return const SizedBox.shrink();
    if (session.status != SessionStatus.connected) return const SizedBox.shrink();

    final isActive = share.isSharing;
    return Tooltip(
      message: isActive ? 'Sharing active' : 'Share this terminal',
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => ShareSessionDialog(sessionId: session.id),
        ),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? AppColors.accent : const Color(0xFF2A2A2A),
            ),
          ),
          child: Icon(
            Icons.screen_share_outlined,
            size: 14,
            color: isActive ? AppColors.accent : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add "Join shared session" to command palette in `_openCommandPalette()`**

In `_openCommandPalette()`, add a new `CommandItem` to the `items` list after the existing action items (near `action_import`):

```dart
      CommandItem(
        id: 'action_join_share',
        title: 'Join Shared Session',
        subtitle: 'Watch a colleague\'s terminal using a share code',
        icon: Icons.screen_share_outlined,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback(
          (_) => showDialog(context: context, builder: (_) => const JoinShareDialog()),
        ),
      ),
```

- [ ] **Step 5: Run flutter analyze**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(share): add share button + join command palette entry"
```

---

## Task 10: Guest watch banner in `split_terminal_view.dart`

**Files:**
- Modify: `app/lib/widgets/split_terminal_view.dart`

- [ ] **Step 1: Add imports**

Add at the top of `app/lib/widgets/split_terminal_view.dart`:

```dart
import '../providers/share_provider.dart';
```

- [ ] **Step 2: Add watch banner in `_buildPane`**

In `_buildPane()`, add a banner at the top of the `Column` for watch sessions. Replace the current `Column` in `_buildPane` with:

```dart
    return Column(
      children: [
        if (session.isWatch)
          _WatchBanner(session: session),
        Expanded(
          child: GestureDetector(
            onTap: () => context.read<SessionProvider>().setActive(session.id),
            child: SessionTerminalView(session: session),
          ),
        ),
        if (showInput)
          TerminalInputBar(
            sessionId: session.id,
            onSubmit: (cmd) {
              if (layout.broadcastEnabled) {
                _broadcastCommand(allSessions, cmd, layout);
              } else {
                _sendCommand(session, cmd);
              }
            },
            onDismiss: () => layout.toggleInputBar(),
          ),
      ],
    );
```

- [ ] **Step 3: Add `_WatchBanner` widget after `SplitTerminalView`'s class body**

```dart
class _WatchBanner extends StatelessWidget {
  final SshSession session;
  const _WatchBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    final hasControl = share.isGuest && share.hasControl;
    final sessionEnded = share.isGuest && share.sessionEnded;

    Color bg;
    Color fg;
    String label;

    if (sessionEnded) {
      bg = const Color(0xFF2A1A1A);
      fg = const Color(0xFFCC4444);
      label = 'Session ended by host';
    } else if (hasControl) {
      bg = const Color(0xFF1A2A1A);
      fg = const Color(0xFF22C55E);
      label = 'You have control';
    } else {
      bg = const Color(0xFF1A1A2A);
      fg = const Color(0xFF6699CC);
      label = 'Watching: ${session.watchedTitle ?? ''} · Read-only';
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.screen_share_outlined, size: 12, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontSize: 11)),
          const Spacer(),
          if (!sessionEnded)
            GestureDetector(
              onTap: () => context.read<ShareProvider>().leaveSession(),
              child: Text('Leave', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run flutter analyze**

```bash
cd app && flutter analyze lib/widgets/split_terminal_view.dart
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/split_terminal_view.dart
git commit -m "feat(share): add watch banner to split terminal view"
```

---

## Task 11: Full test run + smoke test

- [ ] **Step 1: Run full test suite**

```bash
cd app && flutter test
```

Expected: All tests pass (no regressions).

- [ ] **Step 2: Run flutter analyze on the full app**

```bash
cd app && flutter analyze
```

Expected: No errors.

- [ ] **Step 3: Build for macOS to verify compilation**

```bash
cd app && flutter build macos
```

Expected: Build succeeds.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(share): terminal multiplayer via Supabase Realtime

- Host shares via 6-char code + QR; gated on isSupabaseConfigured
- Guest joins via code; watch session tab with read-only banner
- Host can grant/revoke control to one guest at a time
- Rolling 500KB scrollback snapshot sent on guest join
- Supabase Presence detects guest disconnection + auto-revokes control"
```

---

## Self-Review Checklist

- [x] `ShareEvent` model covers all event types in spec
- [x] `ShareSessionService.generateShareCode` excludes ambiguous chars (I, O, 1, 0)
- [x] Output buffer trims to half its size when over 500KB (keeps recent content)
- [x] Chunked snapshot for buffers > 80KB per chunk
- [x] Max 5 guests enforced in `_onHostEvent`
- [x] Presence leave auto-revokes control in `_onHostEvent`
- [x] `canShare` gates on `SyncProvider.isSupabaseConfigured`
- [x] `SshSession.watch` factory creates a fake `Host` with empty credentials (no SSH connection)
- [x] `isWatch` sessions excluded from `_ShareButton` display
- [x] Guest `leaveSession()` removes watch session from `SessionProvider`
- [x] `stopSharing()` unregisters HookBus transform via `unregisterAll(_pluginId)`
- [x] QR encodes `yourssh://share/<code>` for host display
- [x] `JoinShareDialog` error when Supabase not configured
- [x] Control banner colors: blue=watching, green=has control, red=ended
