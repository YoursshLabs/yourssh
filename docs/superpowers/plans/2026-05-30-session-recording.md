# Session Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record SSH terminal sessions to asciicast v2 (`.cast`) files, with per-host auto-record, manual start/stop, a Recording Library screen, and in-app playback.

**Architecture:** `RecordingService` is injected into `SshService` as a passive interceptor — `SshService.openShell()` always calls `writeOutput()` and `onShellClosed()`, which no-op when no recording is active. `RecordingProvider` manages library state and is wired to `SessionProvider` via a `recordingStart` callback (matching the existing `keyLookup`/`hostKeyVerifier` callback pattern).

**Tech Stack:** Flutter/Dart, `xterm` package (already used), `file_picker` (already in pubspec), `path` package (already in pubspec), `dart:io`, `dart:convert`.

---

## File Map

### New files
- `app/lib/models/recording_entry.dart` — immutable metadata for one `.cast` file
- `app/lib/services/recording_service.dart` — write asciicast v2, track active recordings
- `app/lib/providers/recording_provider.dart` — library state, start/stop, disk scan
- `app/lib/widgets/recording_library_screen.dart` — sidebar screen, grouped list, delete
- `app/lib/widgets/recording_player_widget.dart` — in-app asciicast playback
- `app/test/services/recording_service_test.dart`
- `app/test/providers/recording_provider_test.dart`

### Modified files
- `app/lib/models/host.dart` — add `autoRecord: bool`
- `app/lib/services/ssh_service.dart` — add `recordingService` setter, intercept in `openShell` / `_onShellClosed`
- `app/lib/providers/settings_provider.dart` — add `recordingPath: String`
- `app/lib/providers/session_provider.dart` — add `recordingStart` callback, call on auto-record
- `app/lib/main.dart` — wire `RecordingService`, `RecordingProvider`, set callbacks
- `app/lib/screens/main_screen.dart` — add `NavSection.recordings`, red dot on tab, route
- `app/lib/widgets/terminal_view.dart` — record button overlay on `_TerminalWidget`
- `app/lib/widgets/host_detail_panel.dart` — add `autoRecord` toggle + include in `Host` constructor
- `app/lib/widgets/settings_screen.dart` — add recording path row

---

## Task 1: RecordingEntry model

**Files:**
- Create: `app/lib/models/recording_entry.dart`
- Create: `app/test/models/recording_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/recording_entry_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/recording_entry.dart';

void main() {
  test('fromFile parses hostTitle and recordedAt from path', () {
    final file = File('/tmp/Recordings/ubuntu@prod/session_2026-05-30_09-15-30.cast');
    final entry = RecordingEntry.fromPath(file.path);
    expect(entry.hostTitle, 'ubuntu@prod');
    expect(entry.recordedAt, DateTime(2026, 5, 30, 9, 15, 30));
    expect(entry.filePath, file.path);
  });

  test('fromPath handles malformed filename gracefully', () {
    final entry = RecordingEntry.fromPath('/tmp/Recordings/ubuntu@prod/unknown.cast');
    expect(entry.hostTitle, 'ubuntu@prod');
    expect(entry.recordedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/models/recording_entry_test.dart
```
Expected: compilation error (file not found).

- [ ] **Step 3: Create RecordingEntry**

```dart
// app/lib/models/recording_entry.dart
import 'dart:io';

class RecordingEntry {
  final String filePath;
  final String hostTitle;
  final DateTime recordedAt;
  final Duration? duration;
  final int? fileSize;

  const RecordingEntry({
    required this.filePath,
    required this.hostTitle,
    required this.recordedAt,
    this.duration,
    this.fileSize,
  });

  String get fileName => filePath.split(Platform.pathSeparator).last;

  static RecordingEntry fromPath(String filePath) {
    final segments = filePath.split(Platform.pathSeparator);
    final hostTitle = segments.length >= 2 ? segments[segments.length - 2] : 'unknown';
    final name = segments.last;

    DateTime recordedAt;
    try {
      final withoutExt = name.endsWith('.cast') ? name.substring(0, name.length - 5) : name;
      final withoutPrefix = withoutExt.startsWith('session_')
          ? withoutExt.substring('session_'.length)
          : withoutExt;
      final parts = withoutPrefix.split('_');
      if (parts.length == 2) {
        final timePart = parts[1].replaceAll('-', ':');
        recordedAt = DateTime.parse('${parts[0]}T$timePart');
      } else {
        recordedAt = DateTime.fromMillisecondsSinceEpoch(0);
      }
    } catch (_) {
      recordedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    final file = File(filePath);
    final fileSize = file.existsSync() ? file.lengthSync() : null;

    return RecordingEntry(
      filePath: filePath,
      hostTitle: hostTitle,
      recordedAt: recordedAt,
      fileSize: fileSize,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/models/recording_entry_test.dart
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/recording_entry.dart app/test/models/recording_entry_test.dart
git commit -m "feat: add RecordingEntry model for asciicast file metadata"
```

---

## Task 2: RecordingService

**Files:**
- Create: `app/lib/services/recording_service.dart`
- Create: `app/test/services/recording_service_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/services/recording_service_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/recording_service.dart';

void main() {
  late RecordingService service;
  late Directory tmpDir;

  setUp(() async {
    service = RecordingService();
    tmpDir = await Directory.systemTemp.createTemp('rec_test');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('isRecording returns false initially', () {
    expect(service.isRecording('s1'), isFalse);
  });

  test('startRecording creates file with asciicast header', () async {
    final path = '${tmpDir.path}/test.cast';
    await service.startRecording('s1', filePath: path, width: 80, height: 24, title: 'test');
    expect(service.isRecording('s1'), isTrue);
    final lines = await File(path).readAsLines();
    expect(lines.first, contains('"version":2'));
    expect(lines.first, contains('"width":80'));
  });

  test('writeOutput appends event line', () async {
    final path = '${tmpDir.path}/test2.cast';
    await service.startRecording('s1', filePath: path, width: 80, height: 24, title: 't');
    service.writeOutput('s1', 'hello');
    final stopped = await service.stopRecording('s1');
    expect(stopped, path);
    final lines = await File(path).readAsLines();
    expect(lines.length, 2); // header + 1 event
    expect(lines[1], contains('"o"'));
    expect(lines[1], contains('hello'));
  });

  test('writeOutput is no-op when not recording', () {
    expect(() => service.writeOutput('s1', 'data'), returnsNormally);
  });

  test('stopRecording returns null when not recording', () async {
    final result = await service.stopRecording('s1');
    expect(result, isNull);
  });

  test('onShellClosed stops active recording', () async {
    final path = '${tmpDir.path}/test3.cast';
    await service.startRecording('s1', filePath: path, width: 80, height: 24, title: 't');
    expect(service.isRecording('s1'), isTrue);
    service.onShellClosed('s1');
    await Future.delayed(const Duration(milliseconds: 50));
    expect(service.isRecording('s1'), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd app && flutter test test/services/recording_service_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Create RecordingService**

```dart
// app/lib/services/recording_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RecordingService {
  final Map<String, _ActiveRecording> _active = {};

  bool isRecording(String sessionId) => _active.containsKey(sessionId);

  Future<void> startRecording(
    String sessionId, {
    required String filePath,
    required int width,
    required int height,
    required String title,
  }) async {
    if (_active.containsKey(sessionId)) return;
    final dir = File(filePath).parent;
    if (!await dir.exists()) await dir.create(recursive: true);

    final sink = File(filePath).openWrite(mode: FileMode.write);
    final header = {
      'version': 2,
      'width': width,
      'height': height,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'title': title,
    };
    sink.writeln(jsonEncode(header));

    _active[sessionId] = _ActiveRecording(
      sink: sink,
      stopwatch: Stopwatch()..start(),
      filePath: filePath,
    );
  }

  void writeOutput(String sessionId, String data) {
    final rec = _active[sessionId];
    if (rec == null) return;
    final elapsed = rec.stopwatch.elapsedMicroseconds / 1000000.0;
    rec.sink.writeln(jsonEncode([elapsed, 'o', data]));
  }

  Future<String?> stopRecording(String sessionId) async {
    final rec = _active.remove(sessionId);
    if (rec == null) return null;
    rec.stopwatch.stop();
    await rec.sink.flush();
    await rec.sink.close();
    return rec.filePath;
  }

  void onShellClosed(String sessionId) {
    if (isRecording(sessionId)) {
      unawaited(stopRecording(sessionId));
    }
  }
}

class _ActiveRecording {
  final IOSink sink;
  final Stopwatch stopwatch;
  final String filePath;

  _ActiveRecording({
    required this.sink,
    required this.stopwatch,
    required this.filePath,
  });
}
```

Add `import 'dart:async';` is already present. Need to add to the file top of ssh_service.dart (already uses unawaited).

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/services/recording_service_test.dart
```
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/recording_service.dart app/test/services/recording_service_test.dart
git commit -m "feat: add RecordingService for asciicast v2 file writing"
```

---

## Task 3: Host model — add autoRecord field

**Files:**
- Modify: `app/lib/models/host.dart`

- [ ] **Step 1: Add `autoRecord` to `Host`**

In `app/lib/models/host.dart`:

Add field after `detectedOs`:
```dart
bool autoRecord;
```

Update constructor:
```dart
Host({
  String? id,
  required this.label,
  required this.host,
  this.port = 22,
  required this.username,
  this.authType = AuthType.password,
  this.keyId,
  this.group = '',
  this.tags = const [],
  DateTime? createdAt,
  this.detectedOs,
  this.autoRecord = false,   // add this
})  : id = id ?? const Uuid().v4(),
      createdAt = createdAt ?? DateTime.now();
```

Update `toJson()` — add after `'detectedOs'`:
```dart
'autoRecord': autoRecord,
```

Update `fromJson()` — add after `detectedOs`:
```dart
autoRecord: (json['autoRecord'] as bool?) ?? false,
```

Update `copyWith()` — add parameter and usage:
```dart
Host copyWith({
  String? label,
  String? host,
  int? port,
  String? username,
  AuthType? authType,
  String? keyId,
  String? group,
  String? detectedOs,
  bool? autoRecord,   // add this
}) =>
    Host(
      id: id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      keyId: keyId ?? this.keyId,
      group: group ?? this.group,
      tags: tags,
      createdAt: createdAt,
      detectedOs: detectedOs ?? this.detectedOs,
      autoRecord: autoRecord ?? this.autoRecord,   // add this
    );
```

- [ ] **Step 2: Verify analyze passes**

```bash
cd app && flutter analyze lib/models/host.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/host.dart
git commit -m "feat: add autoRecord field to Host model"
```

---

## Task 4: SettingsProvider — add recordingPath

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`

- [ ] **Step 1: Add `recordingPath` field and persistence**

At the top of the file add:
```dart
import 'dart:io';
import 'package:path/path.dart' as p;
```

Add field after `terminalFont`:
```dart
String recordingPath = '';
```

In `_load()`, after loading `terminalFont`, add:
```dart
final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
final defaultPath = p.join(home, 'Documents', 'YourSSH', 'Recordings');
recordingPath = prefs.getString('recordingPath') ?? defaultPath;
```

In `save()` parameter list, add:
```dart
String? recordingPath,
```

In `save()` body, add:
```dart
if (recordingPath != null) this.recordingPath = recordingPath;
```

In `save()` prefs writes, add:
```dart
await prefs.setString('recordingPath', this.recordingPath);
```

- [ ] **Step 2: Verify analyze**

```bash
cd app && flutter analyze lib/providers/settings_provider.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/providers/settings_provider.dart
git commit -m "feat: add recordingPath to SettingsProvider"
```

---

## Task 5: SshService — intercept stdout for recording

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1: Add `recordingService` setter**

In `SshService` class body, after `final Map<String, SystemAgentProxy> _agentProxies = {};` add:
```dart
RecordingService? _recording;
set recordingService(RecordingService? service) => _recording = service;
```

Add import at top:
```dart
import 'recording_service.dart';
```

- [ ] **Step 2: Intercept stdout in `openShell()`**

In `openShell()`, find the stdout listener:
```dart
shell.stdout.cast<List<int>>().listen(
  (data) {
    final text = utf8.convert(data);
    session.terminal.write(text);
    try {
      NotificationService.instance.onTerminalData( ...
```

After `session.terminal.write(text);` add:
```dart
_recording?.writeOutput(session.id, text);
```

- [ ] **Step 3: Stop recording on shell close**

In `_onShellClosed()`, after `NotificationService.instance.removeSession(session.id);` add:
```dart
_recording?.onShellClosed(session.id);
```

- [ ] **Step 4: Verify analyze**

```bash
cd app && flutter analyze lib/services/ssh_service.dart
```
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: wire RecordingService into SshService stdout intercept"
```

---

## Task 6: RecordingProvider

**Files:**
- Create: `app/lib/providers/recording_provider.dart`
- Create: `app/test/providers/recording_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/providers/recording_provider_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/services/recording_service.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('rp_test');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('isRecording returns false initially', () {
    final provider = RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    expect(provider.isRecording('s1'), isFalse);
  });

  test('refreshLibrary finds .cast files', () async {
    final hostDir = Directory('${tmpDir.path}/ubuntu@prod')..createSync();
    File('${hostDir.path}/session_2026-05-30_10-00-00.cast').writeAsStringSync(
      '{"version":2,"width":80,"height":24,"timestamp":1}\n',
    );
    final provider = RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    await provider.refreshLibrary();
    expect(provider.recordings.length, 1);
    expect(provider.recordings.first.hostTitle, 'ubuntu@prod');
  });

  test('deleteRecording removes file and entry', () async {
    final hostDir = Directory('${tmpDir.path}/ubuntu@prod')..createSync();
    final f = File('${hostDir.path}/session_2026-05-30_10-00-00.cast')
      ..writeAsStringSync('{"version":2}\n');
    final provider = RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    await provider.refreshLibrary();
    expect(provider.recordings.length, 1);
    await provider.deleteRecording(f.path);
    expect(provider.recordings.isEmpty, isTrue);
    expect(f.existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd app && flutter test test/providers/recording_provider_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Create RecordingProvider**

```dart
// app/lib/providers/recording_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/recording_entry.dart';
import '../models/ssh_session.dart';
import '../services/recording_service.dart';

class RecordingProvider extends ChangeNotifier {
  final RecordingService _service;
  final String Function() getPath;

  final List<RecordingEntry> _recordings = [];
  final Set<String> _activeIds = {};

  RecordingProvider(this._service, {required this.getPath});

  List<RecordingEntry> get recordings => List.unmodifiable(_recordings);

  Map<String, List<RecordingEntry>> get groupedRecordings {
    final map = <String, List<RecordingEntry>>{};
    for (final r in _recordings) {
      map.putIfAbsent(r.hostTitle, () => []).add(r);
    }
    return map;
  }

  bool isRecording(String sessionId) => _activeIds.contains(sessionId);

  Future<void> startRecording(SshSession session) async {
    if (_activeIds.contains(session.id)) return;

    final basePath = getPath();
    final hostFolder = '${session.host.username}@${session.host.host}';
    final now = DateTime.now();
    final ts = '${now.year}-${_pad(now.month)}-${_pad(now.day)}'
        '_${_pad(now.hour)}-${_pad(now.minute)}-${_pad(now.second)}';
    final filePath = '$basePath/$hostFolder/session_$ts.cast';

    try {
      await _service.startRecording(
        session.id,
        filePath: filePath,
        width: session.terminal.viewWidth,
        height: session.terminal.viewHeight,
        title: '${session.host.username}@${session.host.host}',
      );
      _activeIds.add(session.id);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopRecording(String sessionId) async {
    final path = await _service.stopRecording(sessionId);
    _activeIds.remove(sessionId);
    if (path != null) await refreshLibrary();
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    final basePath = getPath();
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      _recordings.clear();
      notifyListeners();
      return;
    }

    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.cast')) {
        files.add(entity);
      }
    }

    _recordings
      ..clear()
      ..addAll(files.map((f) => RecordingEntry.fromPath(f.path)));
    _recordings.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    notifyListeners();
  }

  Future<void> deleteRecording(String filePath) async {
    try {
      await File(filePath).delete();
    } catch (_) {}
    _recordings.removeWhere((r) => r.filePath == filePath);
    notifyListeners();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/providers/recording_provider_test.dart
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/recording_provider.dart app/test/providers/recording_provider_test.dart
git commit -m "feat: add RecordingProvider for library state management"
```

---

## Task 7: Wire providers in main.dart

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Add imports and instantiation**

Add these imports after existing imports:
```dart
import 'services/recording_service.dart';
import 'providers/recording_provider.dart';
```

In `_YourSSHAppState`, add fields after `_pluginProvider`:
```dart
late final RecordingService _recordingService;
late final RecordingProvider _recordingProvider;
```

In `initState()`, after `_storage = StorageService();` add:
```dart
_recordingService = RecordingService();
_recordingProvider = RecordingProvider(
  _recordingService,
  getPath: () => _settingsProvider.recordingPath,
);
```

After `_ssh = SshService(_storage);` add:
```dart
_ssh.recordingService = _recordingService;
```

After the `_sessionProvider.tmuxEnabled = ...;` line add:
```dart
_sessionProvider.recordingStart = (s) => _recordingProvider.startRecording(s);
```

- [ ] **Step 2: Add RecordingProvider to dispose()**

In `dispose()` after `_pluginProvider.dispose();` add:
```dart
_recordingProvider.dispose();
```

- [ ] **Step 3: Add to MultiProvider**

In `build()`, in the `providers:` list, after `ChangeNotifierProvider.value(value: _pluginProvider),` add:
```dart
ChangeNotifierProvider.value(value: _recordingProvider),
```

- [ ] **Step 4: Verify analyze**

```bash
cd app && flutter analyze lib/main.dart
```
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: wire RecordingService and RecordingProvider in app bootstrap"
```

---

## Task 8: SessionProvider — auto-start recording callback

**Files:**
- Modify: `app/lib/providers/session_provider.dart`

- [ ] **Step 1: Add `recordingStart` callback**

In `SessionProvider` class body, after `Future<void> Function(String hostId, String os)? onOsDetected;` add:
```dart
Future<void> Function(SshSession session)? recordingStart;
```

- [ ] **Step 2: Call it in `_doConnect()`**

In `_doConnect()`, find these two consecutive lines:
```dart
session.errorMessage = null;
notifyListeners();
```

After `notifyListeners();` and before `await _ssh.openShell(...)`, add:
```dart
if (host.autoRecord) {
  unawaited(recordingStart?.call(session) ?? Future.value());
}
```

- [ ] **Step 3: Verify analyze**

```bash
cd app && flutter analyze lib/providers/session_provider.dart
```
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/providers/session_provider.dart
git commit -m "feat: add recordingStart callback to SessionProvider for auto-record"
```

---

## Task 9: Terminal view — record button overlay

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1: Add record button to `_TerminalWidget.build()`**

Add import at top of file:
```dart
import '../providers/recording_provider.dart';
```

In `_TerminalWidgetState.build()`, find the `Stack` widget. Currently it has `TerminalView` and `if (_suggestions.isNotEmpty) Positioned(...)`. Add a new `Positioned` for the record button **before** the suggestions Positioned:

```dart
Positioned(
  top: 8,
  left: 8,
  child: _RecordButton(session: widget.session),
),
```

- [ ] **Step 2: Create `_RecordButton` widget (add at bottom of file)**

```dart
class _RecordButton extends StatelessWidget {
  final SshSession session;
  const _RecordButton({required this.session});

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
              color: isRecording ? Colors.red.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record,
                size: 12,
                color: isRecording ? Colors.red : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                isRecording ? 'REC' : 'REC',
                style: TextStyle(
                  color: isRecording ? Colors.red : Colors.white.withValues(alpha: 0.5),
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

- [ ] **Step 3: Verify analyze**

```bash
cd app && flutter analyze lib/widgets/terminal_view.dart
```
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: add record button overlay to terminal view"
```

---

## Task 10: Session tab — recording indicator (red dot)

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add RecordingProvider import**

Add to the imports at top of `main_screen.dart`:
```dart
import '../providers/recording_provider.dart';
```

- [ ] **Step 2: Add red dot to `_SessionTab`**

In `_SessionTabState.build()`, find the `Row` children inside the `Container`. Find:
```dart
// X close button (left, per image)
GestureDetector(
```

Before the X close button `GestureDetector`, add:
```dart
Consumer<RecordingProvider>(
  builder: (_, rec, __) => rec.isRecording(widget.session.id)
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
```

- [ ] **Step 3: Verify analyze**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
```
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: show red dot recording indicator on session tab"
```

---

## Task 11: Host detail panel — autoRecord toggle

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart`

- [ ] **Step 1: Add `_autoRecord` state**

In `_HostDetailPanelState`, after `bool _testing = false;` add:
```dart
bool _autoRecord = false;
```

In `initState()`, after `_selectedKeyId = h?.keyId;` add:
```dart
_autoRecord = h?.autoRecord ?? false;
```

- [ ] **Step 2: Include `autoRecord` in Host constructor in `_save()`**

In `_save()`, the `Host(...)` constructor call, add after `tags: tags,`:
```dart
autoRecord: _autoRecord,
```

- [ ] **Step 3: Add the toggle to the form UI**

In `build()`, after the last `_Card` (the auth section), find `const SizedBox(height: 16)` before the buttons at the bottom. Add the recording section before it:

```dart
const SizedBox(height: 16),
_sectionLabel('RECORDING'),
const SizedBox(height: 6),
_Card(children: [
  SwitchListTile(
    value: _autoRecord,
    onChanged: (v) => setState(() => _autoRecord = v),
    title: const Text(
      'Auto-record sessions',
      style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
    ),
    subtitle: const Text(
      'Start recording automatically on connect',
      style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
    ),
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    activeColor: AppColors.accent,
  ),
]),
```

To find the right insertion point, look for the row that contains the Save/Connect buttons (near the bottom of the `ListView` in `build()`). Insert immediately before that row.

- [ ] **Step 4: Verify analyze**

```bash
cd app && flutter analyze lib/widgets/host_detail_panel.dart
```
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart
git commit -m "feat: add autoRecord toggle to host detail panel"
```

---

## Task 12: Settings screen — recording path row

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

- [ ] **Step 1: Add recording path row**

Add import at top:
```dart
import 'package:file_picker/file_picker.dart';
```

In `build()`, find where sections are rendered. Locate the terminal section (look for `fontSize`, `terminalTheme` references). Add a new section after the terminal section:

```dart
// Recording section
const SizedBox(height: 24),
_sectionHeader('RECORDING'),
const SizedBox(height: 8),
Consumer<SettingsProvider>(
  builder: (context, settings, _) => _SettingRow(
    label: 'Recording path',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            settings.recordingPath,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () async {
            final result = await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Choose recordings folder',
            );
            if (result != null && context.mounted) {
              await context.read<SettingsProvider>().save(recordingPath: result);
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: AppColors.border),
            foregroundColor: AppColors.textSecondary,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: const Text('Change…'),
        ),
      ],
    ),
  ),
),
```

Note: `_sectionHeader` and `_SettingRow` are helper widgets already used in `settings_screen.dart`. Use whatever helper pattern already exists in the file — inspect the file to match the exact widget names used for other sections.

- [ ] **Step 2: Verify analyze**

```bash
cd app && flutter analyze lib/widgets/settings_screen.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat: add recording path setting to Settings screen"
```

---

## Task 13: RecordingPlayerWidget (in-app asciicast playback)

**Files:**
- Create: `app/lib/widgets/recording_player_widget.dart`

- [ ] **Step 1: Create the player widget**

```dart
// app/lib/widgets/recording_player_widget.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_themes.dart';
import '../providers/settings_provider.dart';
import 'package:provider/provider.dart';

class RecordingPlayerWidget extends StatefulWidget {
  final String filePath;
  const RecordingPlayerWidget({super.key, required this.filePath});

  @override
  State<RecordingPlayerWidget> createState() => _RecordingPlayerWidgetState();
}

class _RecordingPlayerWidgetState extends State<RecordingPlayerWidget> {
  late final Terminal _terminal;
  List<_CastEvent> _events = [];
  int _width = 80;
  int _height = 24;
  int _currentIndex = 0;
  bool _playing = false;
  bool _loading = true;
  String? _error;
  double _speed = 1.0;
  Timer? _timer;

  static const _speeds = [0.5, 1.0, 2.0, 5.0];

  @override
  void initState() {
    super.initState();
    _terminal = Terminal();
    _loadFile();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final lines = await File(widget.filePath).readAsLines();
      if (lines.isEmpty) throw const FormatException('Empty file');

      final header = jsonDecode(lines.first) as Map<String, dynamic>;
      _width = (header['width'] as num).toInt();
      _height = (header['height'] as num).toInt();

      final events = <_CastEvent>[];
      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;
        try {
          final arr = jsonDecode(line) as List;
          if (arr.length >= 3 && arr[1] == 'o') {
            events.add(_CastEvent((arr[0] as num).toDouble(), arr[2] as String));
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _play() {
    if (_events.isEmpty || _playing) return;
    if (_currentIndex >= _events.length) {
      _terminal.buffer.clear();
      _currentIndex = 0;
    }
    setState(() => _playing = true);
    _scheduleNext();
  }

  void _pause() {
    _timer?.cancel();
    if (mounted) setState(() => _playing = false);
  }

  void _scheduleNext() {
    if (!mounted || _currentIndex >= _events.length) {
      if (mounted) setState(() => _playing = false);
      return;
    }

    final event = _events[_currentIndex];
    final prevElapsed = _currentIndex > 0 ? _events[_currentIndex - 1].elapsed : 0.0;
    final gap = (event.elapsed - prevElapsed).clamp(0.0, 5.0);
    final delayMs = (gap / _speed * 1000).round();

    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _terminal.write(event.data);
      _currentIndex++;
      if (mounted) setState(() {});
      _scheduleNext();
    });
  }

  Duration get _totalDuration {
    if (_events.isEmpty) return Duration.zero;
    return Duration(milliseconds: (_events.last.elapsed * 1000).round());
  }

  Duration get _currentPosition {
    if (_events.isEmpty || _currentIndex == 0) return Duration.zero;
    final idx = (_currentIndex - 1).clamp(0, _events.length - 1);
    return Duration(milliseconds: (_events[idx].elapsed * 1000).round());
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
      );
    }

    final settings = context.watch<SettingsProvider>();
    final theme = terminalThemeByName(settings.terminalTheme);
    final progress = _events.isEmpty ? 0.0 : _currentIndex / _events.length;

    return Column(
      children: [
        // Terminal display
        Expanded(
          child: TerminalView(
            _terminal,
            theme: theme,
            textStyle: TerminalStyle(
              fontSize: settings.fontSize,
              fontFamily: settings.terminalFont,
            ),
            padding: EdgeInsets.zero,
            autofocus: false,
          ),
        ),
        // Controls bar
        Container(
          color: AppColors.sidebar,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress
              Row(
                children: [
                  Text(
                    _formatDuration(_currentPosition),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.border,
                      color: AppColors.accent,
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_totalDuration),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: _playing ? _pause : _play,
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<double>(
                    value: _speed,
                    dropdownColor: AppColors.sidebar,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: _speeds
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text('${s}x'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final wasPlaying = _playing;
                      _pause();
                      setState(() => _speed = v);
                      if (wasPlaying) _play();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CastEvent {
  final double elapsed;
  final String data;
  const _CastEvent(this.elapsed, this.data);
}
```

- [ ] **Step 2: Verify analyze**

```bash
cd app && flutter analyze lib/widgets/recording_player_widget.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/recording_player_widget.dart
git commit -m "feat: add RecordingPlayerWidget for in-app asciicast playback"
```

---

## Task 14: RecordingLibraryScreen + NavSection.recordings

**Files:**
- Create: `app/lib/widgets/recording_library_screen.dart`
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Create RecordingLibraryScreen**

```dart
// app/lib/widgets/recording_library_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_entry.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';
import 'recording_player_widget.dart';

class RecordingLibraryScreen extends StatefulWidget {
  const RecordingLibraryScreen({super.key});

  @override
  State<RecordingLibraryScreen> createState() => _RecordingLibraryScreenState();
}

class _RecordingLibraryScreenState extends State<RecordingLibraryScreen> {
  RecordingEntry? _playing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordingProvider>().refreshLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Library list
        SizedBox(
          width: _playing != null ? 360 : double.infinity,
          child: _LibraryList(
            onPlay: (entry) => setState(() => _playing = entry),
            playingPath: _playing?.filePath,
          ),
        ),
        // Player panel
        if (_playing != null) ...[
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: Column(
              children: [
                _PlayerHeader(
                  entry: _playing!,
                  onClose: () => setState(() => _playing = null),
                ),
                Expanded(
                  child: RecordingPlayerWidget(
                    key: ValueKey(_playing!.filePath),
                    filePath: _playing!.filePath,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  final RecordingEntry entry;
  final VoidCallback onClose;
  const _PlayerHeader({required this.entry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.fileName,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: AppColors.textSecondary),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  final ValueChanged<RecordingEntry> onPlay;
  final String? playingPath;
  const _LibraryList({required this.onPlay, this.playingPath});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final groups = provider.groupedRecordings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Text(
                'Recording Library',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14, color: AppColors.textSecondary),
                onPressed: () => provider.refreshLibrary(),
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: groups.isEmpty
              ? const Center(
                  child: Text(
                    'No recordings yet.\nStart a session and press REC.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: groups.entries
                      .map((entry) => _HostGroup(
                            hostTitle: entry.key,
                            recordings: entry.value,
                            onPlay: onPlay,
                            playingPath: playingPath,
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _HostGroup extends StatelessWidget {
  final String hostTitle;
  final List<RecordingEntry> recordings;
  final ValueChanged<RecordingEntry> onPlay;
  final String? playingPath;
  const _HostGroup({
    required this.hostTitle,
    required this.recordings,
    required this.onPlay,
    this.playingPath,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, size: 12, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                hostTitle,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Text(
                '${recordings.length} recording${recordings.length == 1 ? '' : 's'}',
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),
        ...recordings.map((r) => _RecordingRow(
              entry: r,
              isPlaying: r.filePath == playingPath,
              onPlay: () => onPlay(r),
            )),
      ],
    );
  }
}

class _RecordingRow extends StatelessWidget {
  final RecordingEntry entry;
  final bool isPlaying;
  final VoidCallback onPlay;
  const _RecordingRow({required this.entry, required this.isPlaying, required this.onPlay});

  String _fmtSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    return '${(bytes / 1024).round()} KB';
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isPlaying ? AppColors.accent.withValues(alpha: 0.08) : Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDate(entry.recordedAt),
                  style: TextStyle(
                    color: isPlaying ? AppColors.accent : AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (entry.fileSize != null)
                  Text(
                    _fmtSize(entry.fileSize),
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                  ),
              ],
            ),
          ),
          // Play button
          IconButton(
            icon: Icon(
              isPlaying ? Icons.play_circle : Icons.play_circle_outline,
              size: 18,
              color: isPlaying ? AppColors.accent : AppColors.textSecondary,
            ),
            onPressed: onPlay,
            tooltip: 'Play',
            visualDensity: VisualDensity.compact,
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('Delete recording?', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: Text(
          entry.fileName,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<RecordingProvider>().deleteRecording(entry.filePath);
    }
  }
}
```

- [ ] **Step 2: Add `NavSection.recordings` to main_screen.dart**

In `main_screen.dart`, find:
```dart
enum NavSection { hosts, keychain, portForwarding, sftp, localTerminal, knownHosts, settings, plugins }
```

Change to:
```dart
enum NavSection { hosts, keychain, portForwarding, sftp, localTerminal, knownHosts, recordings, settings, plugins }
```

- [ ] **Step 3: Add sidebar import and nav item**

Add import:
```dart
import '../widgets/recording_library_screen.dart';
```

In `_Sidebar.build()`, find:
```dart
const _SectionLabel('TOOLS'),
_navItem(Icons.laptop_mac, 'Local Terminal', NavSection.localTerminal),
```

After `_navItem(Icons.laptop_mac, 'Local Terminal', NavSection.localTerminal),` add:
```dart
_navItem(Icons.video_library_outlined, 'Recordings', NavSection.recordings),
```

- [ ] **Step 4: Add route in `_buildContent()`**

In `_buildContent()`, find the `switch (_nav)` block. Add after `NavSection.localTerminal => const LocalTerminalScreen(),`:
```dart
NavSection.recordings => const RecordingLibraryScreen(),
```

- [ ] **Step 5: Verify analyze**

```bash
cd app && flutter analyze lib/widgets/recording_library_screen.dart lib/screens/main_screen.dart
```
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/recording_library_screen.dart app/lib/screens/main_screen.dart
git commit -m "feat: add Recording Library screen and NavSection.recordings"
```

---

## Task 15: Full analyze + test suite

- [ ] **Step 1: Run full analyze**

```bash
cd app && flutter analyze
```
Expected: No issues.

- [ ] **Step 2: Run all tests**

```bash
cd app && flutter test
```
Expected: All tests pass.

- [ ] **Step 3: Fix any issues found**, then commit fixes.

---

## Self-Review

**Spec coverage check:**
- ✅ Asciinema v2 format — Task 2 (RecordingService writes header + events)
- ✅ Per-host auto-record — Tasks 3, 8, 11 (Host.autoRecord + SessionProvider callback + toggle UI)
- ✅ Manual start/stop — Task 9 (REC button in terminal view)
- ✅ Global recording path — Task 4, 12 (SettingsProvider + Settings screen)
- ✅ Per-host subfolder — Task 6 (RecordingProvider.startRecording constructs path)
- ✅ Recording Library screen — Task 14
- ✅ In-app playback with play/pause/speed — Task 13
- ✅ Recording indicator on session tab — Task 10
- ✅ Wire providers — Task 7

**No placeholders found.**

**Type consistency verified:** `RecordingEntry.fromPath(String)` used in Task 1, 6. `RecordingService` API (`startRecording`, `writeOutput`, `stopRecording`, `onShellClosed`, `isRecording`) consistent across Tasks 2, 5, 6. `RecordingProvider` API (`startRecording(SshSession)`, `stopRecording(String)`, `isRecording(String)`, `refreshLibrary()`, `deleteRecording(String)`) consistent across Tasks 6, 7, 8, 9, 10, 14.
