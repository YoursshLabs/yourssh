# Unified Terminal Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local PTY terminal sessions become first-class tabs in the global top tab bar, unified with SSH sessions (hotkeys, split view, tab metadata, recording).

**Architecture:** A new `TerminalSession` interface is implemented by both `SshSession` and `LocalSession`. `SessionProvider` owns one unified `List<TerminalSession>`; SSH-only logic (reconnect, host-scoped metadata persistence, host teardown) branches on type. `LocalSessionProvider` and `LocalTerminalScreen` are deleted. Spec: `docs/superpowers/specs/2026-06-04-unified-terminal-tabs-design.md`.

**Tech Stack:** Flutter (provider, xterm, flutter_pty local forks). Tests via `flutter test`.

**Compile note:** Tasks 2–7 are a staged type migration. Per-file tests pass at every task, but `flutter analyze` is only fully clean again after Task 8 (consumer sweep). Commit after each task regardless.

All paths relative to repo root. Run tests from `app/`.

---

### Task 1: `TerminalSession` interface + model conformance

**Files:**
- Create: `app/lib/models/terminal_session.dart`
- Modify: `app/lib/models/ssh_session.dart`
- Modify: `app/lib/models/local_session.dart`
- Test: `app/test/models/local_session_test.dart`

- [ ] **Step 1: Write failing tests** — append to the existing `group('LocalSession', ...)` in `app/test/models/local_session_test.dart`:

```dart
    test('tabLabel defaults to "Local N" with increasing N', () {
      final a = LocalSession(terminal: Terminal());
      final b = LocalSession(terminal: Terminal());
      final re = RegExp(r'^Local (\d+)$');
      final ma = re.firstMatch(a.tabLabel)!;
      final mb = re.firstMatch(b.tabLabel)!;
      expect(int.parse(mb.group(1)!), int.parse(ma.group(1)!) + 1);
    });

    test('customLabel overrides default tabLabel', () {
      final s = LocalSession(terminal: Terminal());
      s.customLabel = 'build box';
      expect(s.tabLabel, 'build box');
    });

    test('implements TerminalSession with isLocal true', () {
      final TerminalSession s = LocalSession(terminal: Terminal());
      expect(s.isLocal, isTrue);
      expect(s.isPinned, isFalse);
      expect(s.colorTag, isNull);
    });
```

Add import: `import 'package:yourssh/models/terminal_session.dart';`

- [ ] **Step 2: Run, verify fail**

Run: `cd app && flutter test test/models/local_session_test.dart`
Expected: FAIL (terminal_session.dart does not exist / no tabLabel on LocalSession)

- [ ] **Step 3: Create `app/lib/models/terminal_session.dart`**

```dart
import 'package:xterm/xterm.dart';

/// Common interface for anything that appears as a tab in the global top tab
/// bar: remote SSH sessions and local PTY shells. Consumers that only need
/// tab behavior (label, color, pin, terminal) depend on this; SSH-only
/// features branch on the concrete type.
abstract class TerminalSession {
  String get id;
  Terminal get terminal;

  /// Label shown on the session tab.
  String get tabLabel;

  /// User rename — null means "use the default label".
  String? get customLabel;
  set customLabel(String? value);

  /// Tab color tag as #RRGGBB hex, null = none.
  String? get colorTag;
  set colorTag(String? value);

  bool get isPinned;
  set isPinned(bool value);

  bool get isLocal;
}
```

- [ ] **Step 4: Make `SshSession` implement it** — in `app/lib/models/ssh_session.dart`:

```dart
import 'terminal_session.dart';
// ...
class SshSession implements TerminalSession {
```

and add next to the other getters:

```dart
  @override
  bool get isLocal => false;
```

(Existing `id`, `terminal`, `tabLabel`, `customLabel`, `colorTag`, `isPinned` fields already satisfy the interface.)

- [ ] **Step 5: Make `LocalSession` implement it** — replace the class in `app/lib/models/local_session.dart`:

```dart
// app/lib/models/local_session.dart
import 'package:xterm/xterm.dart';
import 'package:uuid/uuid.dart';
import '../services/pty_runner.dart';
import 'terminal_session.dart';

enum LocalSessionStatus { running, exited, error }

class LocalSession implements TerminalSession {
  /// Monotonic per-app-run counter for default "Local N" tab labels.
  static int _labelCounter = 0;

  @override
  final String id;
  @override
  final Terminal terminal;
  LocalSessionStatus status;
  String? errorMessage;
  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned;
  final int _labelIndex;
  PtyRunner? _pty;

  LocalSession({
    required this.terminal,
    this.status = LocalSessionStatus.running,
    this.customLabel,
    this.colorTag,
    this.isPinned = false,
  })  : id = const Uuid().v4(),
        _labelIndex = ++_labelCounter;

  @override
  String get tabLabel => customLabel ?? 'Local $_labelIndex';

  @override
  bool get isLocal => true;

  void attachPty(PtyRunner pty) {
    _pty = pty;
  }

  void kill() {
    _pty?.kill();
    status = LocalSessionStatus.exited;
  }
}
```

- [ ] **Step 6: Run, verify pass**

Run: `cd app && flutter test test/models/local_session_test.dart test/providers/session_provider_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/lib/models/ app/test/models/local_session_test.dart
git commit -m "feat(model): TerminalSession interface for SSH + local sessions"
```

---

### Task 2: `SessionProvider` unified list

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Modify: `app/lib/services/local_shell_service.dart` (extract `_spawnPty`, add `restartShell`)
- Test: `app/test/providers/session_provider_local_test.dart` (new)

- [ ] **Step 1: Write failing tests** — create `app/test/providers/session_provider_local_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/pty_runner.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _FakePty implements PtyRunner {
  final _output = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get output => _output.stream;
  @override
  void write(Uint8List data) {}
  @override
  void resize(int rows, int cols) {}
  @override
  void kill() => killed = true;
  @override
  Future<int> get exitCode => _exit.future;
}

Host _makeHost(String id) => Host(
      id: id, label: id, host: '$id.example.com', port: 22, username: 'user',
    );

SshSession _makeSsh(String hostId) => SshSession(host: _makeHost(hostId));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late SessionProvider p;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    p = SessionProvider(SshService(StorageService()), TabMetadataService());
    p.localShell =
        LocalShellService(ptyFactory: (shell, c, r, env) => _FakePty());
  });

  tearDown(() {
    p.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  group('unified session list', () {
    test('newLocalSession adds a local session and makes it active', () async {
      await p.newLocalSession();
      expect(p.sessions, hasLength(1));
      expect(p.sessions.single, isA<LocalSession>());
      expect(p.activeSession, same(p.sessions.single));
    });

    test('activateNext cycles across SSH and local in tab order', () async {
      p.addWatchSession(_makeSsh('h1'));
      await p.newLocalSession();
      p.addWatchSession(_makeSsh('h2'));
      // order: [ssh h1, local, ssh h2]; active = ssh h2
      p.activateNext(); // wraps to h1
      expect(p.activeSession, same(p.sessions[0]));
      p.activateNext();
      expect(p.activeSession, isA<LocalSession>());
      p.activatePrev();
      expect(p.activeSession, same(p.sessions[0]));
    });

    test('closeSession on a local session removes it and clears active',
        () async {
      await p.newLocalSession();
      final id = p.sessions.single.id;
      p.closeSession(id);
      expect(p.sessions, isEmpty);
      expect(p.activeSession, isNull);
    });

    test('rename/color/pin work on local sessions without persisting',
        () async {
      await p.newLocalSession();
      p.addWatchSession(_makeSsh('h1'));
      final local = p.sessions.whereType<LocalSession>().single;
      p.renameSession(local.id, 'scratch');
      p.setSessionColor(local.id, '#ef4444');
      p.togglePin(local.id);
      expect(local.customLabel, 'scratch');
      expect(local.colorTag, '#ef4444');
      expect(local.isPinned, isTrue);
      expect(p.sessions.first, same(local)); // pinned moved to front
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('tab_meta_')), isEmpty);
    });

    test('sshSessions excludes locals; activeSshSession falls back', () async {
      final ssh = _makeSsh('h1');
      p.addWatchSession(ssh);
      await p.newLocalSession(); // local is now active
      expect(p.sshSessions, [ssh]);
      expect(p.activeSession, isA<LocalSession>());
      expect(p.activeSshSession, same(ssh));
    });

    test('activeSshSession is null when no SSH sessions exist', () async {
      await p.newLocalSession();
      expect(p.activeSshSession, isNull);
    });

    test('restartLocalSession resets exited status to running', () async {
      await p.newLocalSession();
      final local = p.sessions.whereType<LocalSession>().single;
      local.kill();
      expect(local.status, LocalSessionStatus.exited);
      await p.restartLocalSession(local.id);
      expect(local.status, LocalSessionStatus.running);
    });
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `cd app && flutter test test/providers/session_provider_local_test.dart`
Expected: FAIL (`localShell`, `newLocalSession`, `sshSessions`, etc. undefined)

- [ ] **Step 3: Refactor `LocalShellService`** — in `app/lib/services/local_shell_service.dart`, replace `openShell` with an extracted spawn helper plus `restartShell`:

```dart
  Future<LocalSession> openShell() async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal);
    _sessions[session.id] = session;
    _spawnPty(session);
    return session;
  }

  /// Re-runs the PTY spawn on an exited/errored session, reusing its terminal
  /// (and scrollback). Used by the local pane's "Restart shell" button.
  Future<void> restartShell(LocalSession session) async {
    if (session.status == LocalSessionStatus.running) return;
    session.status = LocalSessionStatus.running;
    session.errorMessage = null;
    _spawnPty(session);
  }

  void _spawnPty(LocalSession session) {
    final terminal = session.terminal;
    final shell =
        resolveShell(Platform.environment, isWindows: Platform.isWindows);

    try {
      final pty = _ptyFactory(
        shell,
        terminal.viewWidth,
        terminal.viewHeight,
        {...Platform.environment, 'TERM': 'xterm-256color'},
      );

      session.attachPty(pty);

      pty.output
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            terminal.write(data);
            try {
              NotificationService.instance.onTerminalData(
                data,
                sessionId: session.id,
                sessionLabel: 'Local Shell',
              );
            } catch (e) {
              debugPrint('[LocalShellService] notification handler threw: $e');
            }
          });

      terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };

      terminal.onResize = (w, h, pw, ph) {
        pty.resize(h, w);
      };

      pty.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
        NotificationService.instance.removeSession(session.id);
      });
    } catch (e) {
      session.status = LocalSessionStatus.error;
      session.errorMessage = e.toString();
    }
  }
```

(Behavior change vs. old code: the session is registered in `_sessions` even when spawn fails — `closeSession` already tolerates that. Recording hooks are added in Task 3.)

- [ ] **Step 4: Unify `SessionProvider`** — in `app/lib/providers/session_provider.dart`:

Add imports:

```dart
import '../models/local_session.dart';
import '../models/terminal_session.dart';
import '../services/local_shell_service.dart';
```

Change the list and getters:

```dart
  final List<TerminalSession> _sessions = [];
  // ...
  /// Set by main.dart; required for newLocalSession/restartLocalSession.
  LocalShellService? localShell;
  // ...
  List<TerminalSession> get sessions => _sessions;

  /// SSH-only consumers (plugin context, devops tools, sync, workspace save).
  List<SshSession> get sshSessions =>
      _sessions.whereType<SshSession>().toList();

  Host? hostForSession(String sessionId) =>
      sshSessions.where((s) => s.id == sessionId).firstOrNull?.host;

  TerminalSession? get activeSession => _sessions.isEmpty
      ? null
      : _sessions.firstWhere(
          (s) => s.id == _activeSessionId,
          orElse: () => _sessions.last,
        );

  /// The active session when it is SSH, else the most recent SSH session.
  /// Used by screens that need *an* SSH target (devops tools, MCP, share).
  SshSession? get activeSshSession {
    final active = activeSession;
    if (active is SshSession) return active;
    return sshSessions.lastOrNull;
  }
```

Add local-session lifecycle methods (after `connect`-related code, before `closeSession`):

```dart
  Future<void> newLocalSession() async {
    final shell = localShell;
    if (shell == null) return;
    final session = await shell.openShell();
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();
  }

  Future<void> restartLocalSession(String sessionId) async {
    final session = _sessionById(sessionId);
    if (session is! LocalSession) return;
    await localShell?.restartShell(session);
    _safeNotify();
  }
```

Branch `closeSession` (local sessions have no reconnect timers or host teardown):

```dart
  void closeSession(String sessionId) {
    final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session is LocalSession) {
      localShell?.closeSession(sessionId);
      _sessions.remove(session);
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
      }
      _safeNotify();
      return;
    }

    _reconnectTimers.remove(sessionId)?.cancel();
    _countdownTimers.remove(sessionId)?.cancel();
    final hostId =
        sshSessions.where((s) => s.id == sessionId).firstOrNull?.host.id;

    _ssh.disconnectSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }

    // If no more sessions for this host remain, tear down the SSH client and jump client.
    if (hostId != null && !sshSessions.any((s) => s.host.id == hostId)) {
      _ssh.disconnect(hostId);
    }

    _safeNotify();
  }
```

Type-guard the remaining SSH-only spots:

```dart
  void removeWatchSession(String sessionId) {
    _sessions.removeWhere(
        (s) => s.id == sessionId && s is SshSession && s.isWatch);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    _safeNotify();
  }

  TerminalSession? _sessionById(String id) =>
      _sessions.where((s) => s.id == id).firstOrNull;
```

In `_persistTabMetadata` change the mirror loop to `for (final s in sshSessions)` (the parameter stays `SshSession`). In `renameSession`, `setSessionColor`, `togglePin` persist only for SSH:

```dart
  void renameSession(String sessionId, String? label) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    session.customLabel = label;
    if (session is SshSession) _persistTabMetadata(session);
    _safeNotify();
  }

  void setSessionColor(String sessionId, String? colorHex) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    session.colorTag = colorHex;
    if (session is SshSession) _persistTabMetadata(session);
    _safeNotify();
  }

  void togglePin(String sessionId) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    session.isPinned = !session.isPinned;
    if (session is SshSession) _persistTabMetadata(session);
    _sortSessions();
    _safeNotify();
  }
```

(`activateNext`, `activatePrev`, `reorderSessionItem`, `_sortSessions`, `connect`, reconnect logic: unchanged — they only use `id`/`isPinned` or are already `SshSession`-typed.)

- [ ] **Step 5: Run, verify pass**

Run: `cd app && flutter test test/providers/session_provider_local_test.dart test/providers/session_provider_test.dart test/services/local_shell_service_test.dart`
Expected: PASS (existing suites must not regress)

- [ ] **Step 6: Commit**

```bash
git add app/lib/providers/session_provider.dart app/lib/services/local_shell_service.dart app/test/providers/session_provider_local_test.dart
git commit -m "feat(sessions): unified TerminalSession list in SessionProvider with local session lifecycle"
```

---

### Task 3: Recording for local sessions

**Files:**
- Modify: `app/lib/services/local_shell_service.dart`
- Modify: `app/lib/providers/recording_provider.dart`
- Create: `app/lib/widgets/record_button.dart`
- Modify: `app/lib/widgets/terminal_view.dart` (use shared button)
- Test: `app/test/services/local_shell_service_test.dart`, `app/test/providers/recording_provider_test.dart`

- [ ] **Step 1: Write failing test for PTY → RecordingService pass-through** — append to `app/test/services/local_shell_service_test.dart` (reuse the file's existing fake-pty factory pattern; the fake must expose its output `StreamController` so the test can emit data):

```dart
  group('recording intercept', () {
    test('pty output is forwarded to RecordingService', () async {
      final dir = await Directory.systemTemp.createTemp('ys_rec');
      addTearDown(() => dir.delete(recursive: true));

      final rec = RecordingService();
      final service = LocalShellService(
        ptyFactory: (shell, c, r, env) => fakePty, // file's existing fake
      )..recordingService = rec;

      final session = await service.openShell();
      await rec.startRecording(
        session.id,
        filePath: '${dir.path}/local/session_test.cast',
        width: 80,
        height: 24,
        title: 'Local terminal',
      );

      fakePty.emitOutput('hello-from-pty');
      await Future<void>.delayed(Duration.zero);

      final path = await rec.stopRecording(session.id);
      expect(path, isNotNull);
      final content = await File(path!).readAsString();
      expect(content, contains('hello-from-pty'));
    });
  });
```

Add the needed imports (`dart:io`, `package:yourssh/services/recording_service.dart`) and, if the file's fake pty lacks an emit helper, add `void emitOutput(String s) => _output.add(utf8.encode(s));` to it.

- [ ] **Step 2: Write failing test for local recording path** — append to `app/test/providers/recording_provider_test.dart` (match the file's existing setup conventions):

```dart
  test('local session records into local/ folder', () async {
    final dir = await Directory.systemTemp.createTemp('ys_rec_prov');
    addTearDown(() => dir.delete(recursive: true));
    final provider =
        RecordingProvider(RecordingService(), getPath: () => dir.path);
    final session = LocalSession(terminal: Terminal());

    await provider.startRecording(session);
    expect(provider.isRecording(session.id), isTrue);

    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.cast'))
        .toList();
    expect(files, hasLength(1));
    expect(files.single.path, contains('${Platform.pathSeparator}local${Platform.pathSeparator}'));

    await provider.stopRecording(session.id);
    expect(provider.isRecording(session.id), isFalse);
  });
```

Imports needed: `dart:io`, `package:xterm/xterm.dart`, `package:yourssh/models/local_session.dart`.

- [ ] **Step 3: Run, verify fail**

Run: `cd app && flutter test test/services/local_shell_service_test.dart test/providers/recording_provider_test.dart`
Expected: FAIL (`recordingService` setter missing; `startRecording` rejects `LocalSession`)

- [ ] **Step 4: Wire `LocalShellService` recording hooks** — in `app/lib/services/local_shell_service.dart`:

```dart
import 'recording_service.dart';
// ...
class LocalShellService {
  // ...
  /// Passive intercept (same pattern as SshService): set by main.dart,
  /// no-ops when the session is not being recorded.
  RecordingService? recordingService;
```

In `_spawnPty`'s output listener, after `terminal.write(data);`:

```dart
            recordingService?.writeOutput(session.id, data);
```

In `_spawnPty`'s exit handler, before `NotificationService.instance.removeSession(...)`:

```dart
        recordingService?.onShellClosed(session.id);
```

And in `closeSession`, before `_sessions[sessionId]?.kill();`:

```dart
    recordingService?.onShellClosed(sessionId);
```

- [ ] **Step 5: Generalize `RecordingProvider`** — in `app/lib/providers/recording_provider.dart`:

```dart
import '../models/terminal_session.dart';
// ...
  void Function(TerminalSession session, Object error)? onStartFailed;
// ...
  Future<void> startRecording(TerminalSession session) async {
    if (_activeIds.contains(session.id)) return;

    final basePath = getPath();
    final hostFolder = session is SshSession
        ? '${session.host.username}@${session.host.host}'
        : 'local';
    final title = session is SshSession
        ? '${session.host.username}@${session.host.host}'
        : 'Local terminal';
    final now = DateTime.now();
    final ts = '${now.year}-${_pad(now.month)}-${_pad(now.day)}'
        '_${_pad(now.hour)}-${_pad(now.minute)}-${_pad(now.second)}';
    final filePath = '$basePath/$hostFolder/session_$ts.cast';

    _activeIds.add(session.id);
    try {
      await _service.startRecording(
        session.id,
        filePath: filePath,
        width: session.terminal.viewWidth,
        height: session.terminal.viewHeight,
        title: title,
      );
      notifyListeners();
    } catch (e) {
      _activeIds.remove(session.id);
      notifyListeners();
      onStartFailed?.call(session, e);
    }
  }
```

(Keep the `import '../models/ssh_session.dart';` — the type checks need it.)

- [ ] **Step 6: Extract shared `RecordButton`** — create `app/lib/widgets/record_button.dart` with the body of `_RecordButton` from `app/lib/widgets/terminal_view.dart:471-523`, renamed public and retyped:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/terminal_session.dart';
import '../providers/recording_provider.dart';

/// Floating REC toggle shown over a terminal pane (SSH and local).
class RecordButton extends StatelessWidget {
  final TerminalSession session;
  const RecordButton({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final isRecording = provider.isRecording(session.id);

    return Tooltip(
      message: isRecording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: () {
          if (isRecording) {
            provider.stopRecording(session.id);
          } else {
            provider.startRecording(session);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isRecording
                  ? Colors.red.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRecording
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record,
                size: 12,
                color: isRecording
                    ? Colors.red
                    : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'REC',
                style: TextStyle(
                  color: isRecording
                      ? Colors.red
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

In `terminal_view.dart`: delete the `_RecordButton` class, add `import 'record_button.dart';`, and replace the usage at line ~452 with `child: RecordButton(session: widget.session),`.

- [ ] **Step 7: Run, verify pass**

Run: `cd app && flutter test test/services/local_shell_service_test.dart test/providers/recording_provider_test.dart test/services/recording_service_test.dart`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add app/lib/services/local_shell_service.dart app/lib/providers/recording_provider.dart app/lib/widgets/record_button.dart app/lib/widgets/terminal_view.dart app/test/
git commit -m "feat(recording): asciicast recording for local terminal sessions"
```

---

### Task 4: `LocalTerminalPane` widget

**Files:**
- Create: `app/lib/widgets/local_terminal_pane.dart`
- Test: `app/test/widgets/local_terminal_pane_test.dart` (new)

- [ ] **Step 1: Write failing widget test** — create `app/test/widgets/local_terminal_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/widgets/local_terminal_pane.dart';

void main() {
  testWidgets('exited pane shows Restart shell and fires onRestart',
      (tester) async {
    final session = LocalSession(
      terminal: Terminal(),
      status: LocalSessionStatus.exited,
    );
    var restarted = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LocalTerminalPane(
          session: session,
          onRestart: () => restarted = true,
        ),
      ),
    ));

    expect(find.text('Shell exited'), findsOneWidget);
    await tester.tap(find.text('Restart shell'));
    expect(restarted, isTrue);
  });

  testWidgets('error pane shows the error message', (tester) async {
    final session = LocalSession(
      terminal: Terminal(),
      status: LocalSessionStatus.error,
    )..errorMessage = 'spawn failed';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LocalTerminalPane(session: session, onRestart: () {}),
      ),
    ));

    expect(find.text('spawn failed'), findsOneWidget);
    expect(find.text('Restart shell'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `cd app && flutter test test/widgets/local_terminal_pane_test.dart`
Expected: FAIL (local_terminal_pane.dart does not exist)

- [ ] **Step 3: Create `app/lib/widgets/local_terminal_pane.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';
import '../providers/settings_provider.dart';
import 'record_button.dart';

/// Terminal pane for a local PTY session inside the split terminal workspace.
/// Mirrors SessionTerminalView's status handling, minus SSH-only features
/// (search, shell integration, command gutter).
class LocalTerminalPane extends StatelessWidget {
  final LocalSession session;
  final VoidCallback onRestart;
  const LocalTerminalPane(
      {super.key, required this.session, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return switch (session.status) {
      LocalSessionStatus.error => _statusView(
          Icons.error_outline,
          session.errorMessage ?? 'Failed to start shell',
          Colors.red,
        ),
      LocalSessionStatus.exited =>
        _statusView(Icons.link_off, 'Shell exited', Colors.grey),
      LocalSessionStatus.running => _terminal(context),
    };
  }

  Widget _terminal(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Stack(
      children: [
        TerminalView(
          key: ValueKey(session.id),
          session.terminal,
          autofocus: true,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: RecordButton(session: session),
        ),
      ],
    );
  }

  Widget _statusView(IconData icon, String message, Color color) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(
                    color: color, fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Restart shell'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `cd app && flutter test test/widgets/local_terminal_pane_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/local_terminal_pane.dart app/test/widgets/local_terminal_pane_test.dart
git commit -m "feat(ui): LocalTerminalPane with status overlay and restart"
```

---

### Task 5: `SplitTerminalView` type branching

**Files:**
- Modify: `app/lib/widgets/split_terminal_view.dart`

- [ ] **Step 1: Retype and branch.** Add imports:

```dart
import '../models/local_session.dart';
import '../models/terminal_session.dart';
import 'local_terminal_pane.dart';
```

Retype the helpers (`Terminal.textInput` works for both types):

```dart
  void _sendCommand(TerminalSession session, String command) {
    session.terminal.textInput(command);
  }

  void _broadcastCommand(
    List<TerminalSession> sessions,
    String command,
    TerminalLayoutProvider layout,
  ) {
    if (!layout.broadcastEnabled) return;
    for (final s in sessions) {
      s.terminal.textInput(command);
    }
  }
```

Snippet target supports running local shells:

```dart
  bool _canRunSnippetTarget(BuildContext context) {
    final active = context.read<SessionProvider>().activeSession;
    return switch (active) {
      SshSession s => !s.isWatch && s.status == SessionStatus.connected,
      LocalSession s => s.status == LocalSessionStatus.running,
      _ => false,
    };
  }

  void _runSnippetOnActive(BuildContext context, String command) {
    if (!_canRunSnippetTarget(context)) return;
    context.read<SessionProvider>().activeSession!.terminal
        .textInput('$command\n');
  }
```

Retype `_buildPanes` signature: `List<TerminalSession> sessions, TerminalSession? active` (body unchanged). Retype and branch `_buildPane`:

```dart
  Widget _buildPane(
    BuildContext context,
    int paneIndex,
    TerminalSession session,
    List<TerminalSession> allSessions,
    TerminalLayoutProvider layout,
  ) {
    final showInput = layout.inputBarVisible && paneIndex == 0 ||
        (layout.inputBarVisible && layout.broadcastEnabled);

    return Column(
      children: [
        if (session is SshSession && session.isWatch)
          _WatchBanner(session: session),
        Expanded(
          child: GestureDetector(
            onTap: () => context.read<SessionProvider>().setActive(session.id),
            child: _paneContent(context, session),
          ),
        ),
        if (showInput)
          TerminalInputBar(
            sessionId: session.id,
            cwd: context.select<ShellIntegrationProvider, String?>(
                (p) => p.cwdFor(session.id)),
            // Path completion needs a remote lister — SSH only.
            listDir: session is SshSession
                ? (dir) =>
                    context.read<SshService>().listDirectory(session.host, dir)
                : null,
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
  }

  Widget _paneContent(BuildContext context, TerminalSession session) {
    if (session is LocalSession) {
      return LocalTerminalPane(
        key: ValueKey(session.id),
        session: session,
        onRestart: () =>
            context.read<SessionProvider>().restartLocalSession(session.id),
      );
    }
    return SessionTerminalView(
        key: ValueKey(session.id), session: session as SshSession);
  }
```

- [ ] **Step 2: Sanity-analyze just this file's deps**

Run: `cd app && flutter analyze lib/widgets/split_terminal_view.dart lib/widgets/local_terminal_pane.dart`
Expected: no errors in these two files (other files still pending migration may error — ignore those here)

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/split_terminal_view.dart
git commit -m "feat(split-view): render local sessions as panes alongside SSH"
```

---

### Task 6: `main.dart` wiring + plugin context

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/plugins/plugin_context_impl.dart`

- [ ] **Step 1: Wire `LocalShellService` in `main.dart`.**

Add field to `_YourSSHAppState`:

```dart
  late final LocalShellService _localShell;
```

In `initState()` after `_recordingService = RecordingService();`:

```dart
    _localShell = LocalShellService();
    _localShell.recordingService = _recordingService;
```

After `_sessionProvider = SessionProvider(...)`:

```dart
    _sessionProvider.localShell = _localShell;
```

Add `import 'services/local_shell_service.dart';` (match the file's existing import style). Remove the `LocalSessionProvider` import and delete line 335: `ChangeNotifierProvider(create: (_) => LocalSessionProvider()),`.

- [ ] **Step 2: SSH-only filtering in `_SshBridgeAdapter` (main.dart:49-72):**

```dart
  @override
  List<Map<String, dynamic>> activeSessions() {
    return _getSessionProvider().sshSessions.map((s) => {
          'sessionId': s.id,
          'host': s.host.host,
          'username': s.host.username,
          'port': s.host.port,
          'connected': s.status.name == 'connected',
        }).toList();
  }

  @override
  Future<Map<String, dynamic>> execCommand(
      String sessionId, String command) async {
    final session = _getSessionProvider()
        .sshSessions
        .firstWhere((s) => s.id == sessionId);
    final result = await _getSshService().exec(session.host, command);
    return {
      'stdout': result.stdout,
      'stderr': result.stderr,
      'exitCode': result.exitCode,
    };
  }
```

And `onGuestInput` (main.dart:239-246):

```dart
      final session = _sessionProvider.sshSessions
          .where((s) => s.id == sessionId && !s.isWatch)
          .firstOrNull;
```

- [ ] **Step 3: `plugin_context_impl.dart` — plugins see only SSH sessions:**

```dart
  @override
  List<SSHSessionProxy> get activeSessions => _sessions.sshSessions
      .map((s) => _toProxy(s, isActive: _sessions.activeSession?.id == s.id))
      .toList();

  @override
  SSHSessionProxy? get activeSession {
    final session = _sessions.activeSshSession;
    if (session == null) return null;
    return _toProxy(session, isActive: true);
  }
```

And in `sendInput`:

```dart
    final session =
        _sessions.sshSessions.where((s) => s.id == sessionId).firstOrNull;
```

- [ ] **Step 4: Run provider + plugin tests**

Run: `cd app && flutter test test/providers/ test/plugins/`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart app/lib/plugins/plugin_context_impl.dart
git commit -m "refactor(wiring): inject LocalShellService; SSH-only views for plugins and share"
```

---

### Task 7: `main_screen.dart` — tab bar, sidebar action, delete old screen

**Files:**
- Modify: `app/lib/screens/main_screen.dart`
- Delete: `app/lib/widgets/local_terminal_screen.dart`, `app/lib/providers/local_session_provider.dart`

- [ ] **Step 1: Imports and enum.** Remove `import '../widgets/local_terminal_screen.dart';`. Add:

```dart
import '../models/local_session.dart';
import '../models/terminal_session.dart';
```

Change the enum (remove `localTerminal`):

```dart
enum NavSection { hosts, keychain, portForwarding, sftp, knownHosts, recordings, settings, plugins }
```

- [ ] **Step 2: Add the open-local-terminal action** to `_MainScreenState` (near `_openHostPanel`):

```dart
  /// Sidebar "Local Terminal" + command palette entry: focus the last local
  /// tab if one exists (list order approximates recency), else open a new one.
  void _openLocalTerminal() {
    final provider = context.read<SessionProvider>();
    final existing = provider.sessions.whereType<LocalSession>().lastOrNull;
    if (existing != null) {
      provider.setActive(existing.id);
    } else {
      unawaited(provider.newLocalSession());
    }
    setState(() => _viewingTerminal = true);
  }
```

- [ ] **Step 3: Reroute the three `NavSection.localTerminal` call sites:**

1. Command palette item (~line 417): replace the `execute:` closure with `execute: _openLocalTerminal,`
2. `_buildContent` → `HostsDashboard` (~line 723): `onOpenLocalTerminal: _openLocalTerminal,`
3. `_buildContent` switch (~line 732): delete the `NavSection.localTerminal => const LocalTerminalScreen(),` arm.

- [ ] **Step 4: Sidebar item becomes an action.** Add to `_Sidebar`:

```dart
  final VoidCallback onOpenLocalTerminal;
```

(constructor: `required this.onOpenLocalTerminal`). Replace `_navItem(Icons.laptop_mac, 'Local Terminal', NavSection.localTerminal),` (~line 797) with:

```dart
          _NavItem(
            icon: Icons.laptop_mac,
            label: 'Local Terminal',
            selected: false,
            onTap: onOpenLocalTerminal,
          ),
```

At the `_Sidebar(...)` construction site (~line 547) add `onOpenLocalTerminal: _openLocalTerminal,`.

- [ ] **Step 5: Retype `_TopTabBar` and add the "+" menu.**

`_TopTabBar` fields: `List<TerminalSession> sessions`, `TerminalSession? active`, plus a new `final VoidCallback onAddLocalSession;` (constructor required). Replace `_AddTabBtn(onTap: onAddSession)` with:

```dart
          _AddTabBtn(onNewSsh: onAddSession, onNewLocal: onAddLocalSession),
```

Rewrite `_AddTabBtn` as a menu trigger:

```dart
class _AddTabBtn extends StatefulWidget {
  final VoidCallback onNewSsh;
  final VoidCallback onNewLocal;
  const _AddTabBtn({required this.onNewSsh, required this.onNewLocal});

  @override
  State<_AddTabBtn> createState() => _AddTabBtnState();
}

class _AddTabBtnState extends State<_AddTabBtn> {
  bool _hovered = false;

  Future<void> _showAddMenu() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height));
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        const PopupMenuItem(
          value: 'ssh',
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('New SSH session',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        const PopupMenuItem(
          value: 'local',
          child: Row(children: [
            Icon(Icons.laptop_mac, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('New local terminal',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
      ],
    );
    switch (result) {
      case 'ssh':
        widget.onNewSsh();
      case 'local':
        widget.onNewLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _showAddMenu,
        child: Container(
          width: 36,
          height: 38,
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 16,
            color: _hovered ? const Color(0xFFAAAAAA) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}
```

At the `_TopTabBar(...)` construction site in `build()` add:

```dart
            onAddLocalSession: () {
              setState(() => _viewingTerminal = true);
              unawaited(context.read<SessionProvider>().newLocalSession());
            },
```

- [ ] **Step 6: `_SessionTab` for both types.** Retype `final TerminalSession session;` (and keep `provider` as `SessionProvider`). In `build()`, introduce `final session = widget.session;` at the top and replace the health-dot block (lines ~1337-1351):

```dart
              // Connection health dot for SSH; laptop glyph for local tabs.
              if (session is SshSession && !session.isWatch)
                Builder(builder: (context) {
                  final health = context
                      .watch<HealthMonitorService>()
                      .healthFor(session.host.id);
                  final tone = badgeToneFor(session.status, health);
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Tooltip(
                      message: _healthTooltip(session, health),
                      child: HealthDot(tone: tone),
                    ),
                  );
                })
              else if (session.isLocal)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child:
                      Icon(Icons.laptop_mac, size: 12, color: Color(0xFF888888)),
                ),
```

Update remaining `widget.session.isWatch` references in this widget the same way (`session is SshSession && session.isWatch`). The context menu, rename, color, and pin code is type-agnostic — no changes.

- [ ] **Step 7: `_buildContent` + workspace save + recording error toast.**

`_buildContent(TerminalSession? active)` — guard the share button row:

```dart
                    children: [
                      const NetworkStatsOverlay(),
                      const SizedBox(width: 8),
                      if (active is SshSession) ...[
                        _ShareButton(session: active),
                        const SizedBox(width: 8),
                      ],
                      _AiChatToggle(
```

`_saveWorkspaceNow` (~line 239) — persist SSH tabs only (local sessions are ephemeral by design):

```dart
  void _saveWorkspaceNow() {
    final sessions = _sessionProvider?.sshSessions;
    final layout = _layoutProvider;
    if (sessions == null || layout == null) return;
    final active = _sessionProvider?.activeSession;
    final snapshot = WorkspaceSnapshot(
      hostIds: sessions.map((s) => s.host.id).toList(),
      activeHostId: active is SshSession ? active.host.id : null,
      layout: layout.layout,
      inputBarVisible: layout.inputBarVisible,
    );
    _workspaceSvc.save(snapshot);
  }
```

`_restoreWorkspace` (~line 334): the `sessionProvider.sessions.where((s) => s.host.id == ...)` lookup must use `sessionProvider.sshSessions` instead.

`_wireRecordingErrors` (~line 98): `'Recording failed for ${session.tabLabel}: $error'` (matches the new `TerminalSession` callback signature).

- [ ] **Step 8: Delete the dead files**

```bash
git rm app/lib/widgets/local_terminal_screen.dart app/lib/providers/local_session_provider.dart
```

- [ ] **Step 9: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(tabs): local terminal sessions join the global top tab bar"
```

---

### Task 8: Remaining `activeSession` consumers + full verification

**Files:**
- Modify: `app/lib/widgets/mcp_server_screen.dart` (lines 38, 77)
- Modify: `app/lib/widgets/cloudflare_tunnel_screen.dart` (lines 35, 47, 75)
- Modify: `app/lib/widgets/mail_catcher_screen.dart` (lines 36, 56, 64, 137)
- Modify: `app/lib/widgets/devops_tools_screen.dart` (lines 121, 288)
- Modify: `app/lib/widgets/containers_screen.dart` (line 56)
- Modify: `app/lib/widgets/network_stats_overlay.dart` (line 28)

- [ ] **Step 1: Sidebar tool screens → `activeSshSession`.** These screens need *an SSH target*; the fallback keeps them working while a local tab is focused. In mcp_server / cloudflare_tunnel / mail_catcher / devops_tools screens, mechanically replace every `context.read<SessionProvider>().activeSession` / `context.watch<SessionProvider>().activeSession` with `.activeSshSession` (same read/watch).

- [ ] **Step 2: `containers_screen.dart:56`** — `context.watch<SessionProvider>().sessions` → `context.watch<SessionProvider>().sshSessions`.

- [ ] **Step 3: `network_stats_overlay.dart:28`** — the overlay shows stats *for the focused session*, so a local tab must hide it rather than fall back to another host:

```dart
    final active = context.read<SessionProvider>().activeSession;
    final session = active is SshSession ? active : null;
```

(keep the file's existing null handling below; add the `SshSession` import if missing).

- [ ] **Step 4: Full analyze — must be clean now**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

If anything still references the old types (e.g. a widget test or a file missed above), the analyzer output is the worklist — fix each the same way (SSH-only consumer → `sshSessions`/`activeSshSession`; tab-level consumer → `TerminalSession`).

- [ ] **Step 5: Full test suite**

Run: `cd app && flutter test`
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add app/lib
git commit -m "refactor(ui): SSH-only consumers use sshSessions/activeSshSession"
```

---

### Task 9: Manual smoke test (macOS)

- [ ] **Step 1:** `cd app && flutter run -d macos`, then verify:
1. Sidebar **Local Terminal** opens a `Local 1` tab in the top row; typing works.
2. **+** button shows the two-item menu; "New local terminal" opens `Local 2`.
3. Ctrl+Tab-equivalent hotkeys cycle through SSH and local tabs together.
4. Right-click a local tab: rename / color / pin / close all work; pin moves it before unpinned tabs.
5. Split horizontal with one SSH + one local session: both panes render; local pane shows REC button; recording produces a `.cast` under `local/` in the recordings library.
6. `exit` in a local shell shows the "Shell exited" overlay; **Restart shell** brings it back.
7. Quit + relaunch: SSH tabs restore, local tabs do not (by design).

- [ ] **Step 2:** Report results; fix anything broken before declaring done.
