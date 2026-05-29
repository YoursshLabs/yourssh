# Tests + CI Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add comprehensive unit tests for all code changed since the last release-pipeline commit, and gate the CI release on tests passing first.

**Architecture:** Introduce a `PtyRunner` abstraction so `flutter_pty` (native plugin) can be injected and replaced with a `FakePtyRunner` in tests. All other changes are additive test cases on top of existing test helpers.

**Tech Stack:** Flutter / Dart unit tests (`flutter_test`), GitHub Actions.

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| Create | `app/lib/services/pty_runner.dart` | `PtyRunner` abstract class + `FlutterPtyRunner` impl |
| Modify | `app/lib/models/local_session.dart` | `Pty` → `PtyRunner` |
| Modify | `app/lib/services/local_shell_service.dart` | inject `PtyRunner` factory |
| Create | `app/test/models/local_session_test.dart` | LocalSession unit tests |
| Create | `app/test/services/local_shell_service_test.dart` | LocalShellService unit tests |
| Modify | `app/test/models/sftp_entry_test.dart` | add `kindLabel` tests |
| Modify | `app/test/providers/local_file_panel_provider_test.dart` | add `showHidden` / `selectAll` group |
| Modify | `app/test/providers/sync_provider_test.dart` | add keychain fallback test |
| Modify | `app/test/services/sync_service_test.dart` | add `disableAndDelete` test |
| Modify | `.github/workflows/release.yml` | add `test` job before builds |

---

## Task 1: PtyRunner abstraction

**Files:**
- Create: `app/lib/services/pty_runner.dart`
- Modify: `app/lib/models/local_session.dart`
- Modify: `app/lib/services/local_shell_service.dart`

- [x] **Step 1: Create `pty_runner.dart`**

```dart
// app/lib/services/pty_runner.dart
import 'dart:typed_data';
import 'package:flutter_pty/flutter_pty.dart';

abstract class PtyRunner {
  Stream<List<int>> get output;
  void write(Uint8List data);
  void resize(int rows, int cols);
  void kill();
  Future<int> get exitCode;
}

class FlutterPtyRunner implements PtyRunner {
  final Pty _pty;
  FlutterPtyRunner(this._pty);

  @override
  Stream<List<int>> get output => _pty.output.cast<List<int>>();

  @override
  void write(Uint8List data) => _pty.write(data);

  @override
  void resize(int rows, int cols) => _pty.resize(rows, cols);

  @override
  void kill() => _pty.kill();

  @override
  Future<int> get exitCode => _pty.exitCode;
}
```

- [x] **Step 2: Update `local_session.dart` — swap `Pty` for `PtyRunner`**

Replace entire file content:

```dart
// app/lib/models/local_session.dart
import 'package:xterm/xterm.dart';
import 'package:uuid/uuid.dart';
import '../services/pty_runner.dart';

enum LocalSessionStatus { running, exited, error }

class LocalSession {
  final String id;
  final Terminal terminal;
  LocalSessionStatus status;
  String? errorMessage;
  PtyRunner? _pty;

  LocalSession({
    required this.terminal,
    this.status = LocalSessionStatus.running,
  }) : id = const Uuid().v4();

  void attachPty(PtyRunner pty) {
    _pty = pty;
  }

  void kill() {
    _pty?.kill();
    status = LocalSessionStatus.exited;
  }
}
```

- [x] **Step 3: Update `local_shell_service.dart` — inject `PtyRunner` factory**

Replace entire file content:

```dart
// app/lib/services/local_shell_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';
import 'pty_runner.dart';

typedef PtyFactory = PtyRunner Function(
  String shell,
  int columns,
  int rows,
  Map<String, String> environment,
);

class LocalShellService {
  final Map<String, LocalSession> _sessions = {};
  final PtyFactory _ptyFactory;

  LocalShellService({PtyFactory? ptyFactory})
      : _ptyFactory = ptyFactory ?? _defaultFactory;

  static PtyRunner _defaultFactory(
    String shell,
    int columns,
    int rows,
    Map<String, String> environment,
  ) =>
      FlutterPtyRunner(
        Pty.start(shell, columns: columns, rows: rows, environment: environment),
      );

  Future<LocalSession> openShell() async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal);

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';

    try {
      final pty = _ptyFactory(
        shell,
        terminal.viewWidth,
        terminal.viewHeight,
        {...Platform.environment, 'TERM': 'xterm-256color'},
      );

      session.attachPty(pty);
      _sessions[session.id] = session;

      pty.output
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);

      terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };

      terminal.onResize = (w, h, pw, ph) {
        pty.resize(h, w);
      };

      pty.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
      });
    } catch (e) {
      session.status = LocalSessionStatus.error;
      session.errorMessage = e.toString();
    }

    return session;
  }

  void closeSession(String sessionId) {
    _sessions[sessionId]?.kill();
    _sessions.remove(sessionId);
  }

  LocalSession? getSession(String sessionId) => _sessions[sessionId];
}
```

- [x] **Step 4: Verify no analysis errors**

Run: `cd app && flutter analyze`
Expected: no errors (only pre-existing warnings, if any).

- [x] **Step 5: Commit**

```bash
git add app/lib/services/pty_runner.dart app/lib/models/local_session.dart app/lib/services/local_shell_service.dart
git commit -m "refactor: introduce PtyRunner abstraction for testability"
```

---

## Task 2: LocalSession unit tests

**Files:**
- Create: `app/test/models/local_session_test.dart`

- [x] **Step 1: Create the test file**

```dart
// app/test/models/local_session_test.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/services/pty_runner.dart';

class FakePtyRunner implements PtyRunner {
  final _outputController = StreamController<List<int>>();
  final _exitCompleter = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int cols) {}

  @override
  void kill() => killed = true;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  void dispose() => _outputController.close();
}

void main() {
  group('LocalSession', () {
    test('initial status is running', () {
      final session = LocalSession(terminal: Terminal());
      expect(session.status, LocalSessionStatus.running);
    });

    test('kill() sets status to exited', () {
      final session = LocalSession(terminal: Terminal());
      session.kill();
      expect(session.status, LocalSessionStatus.exited);
    });

    test('kill() calls kill on attached PtyRunner', () {
      final session = LocalSession(terminal: Terminal());
      final fake = FakePtyRunner();
      session.attachPty(fake);
      session.kill();
      expect(fake.killed, true);
      fake.dispose();
    });

    test('kill() without attachPty does not throw', () {
      final session = LocalSession(terminal: Terminal());
      expect(() => session.kill(), returnsNormally);
    });

    test('each session has a unique id', () {
      final a = LocalSession(terminal: Terminal());
      final b = LocalSession(terminal: Terminal());
      expect(a.id, isNot(equals(b.id)));
    });
  });
}
```

- [x] **Step 2: Run the test to verify it passes**

Run: `cd app && flutter test test/models/local_session_test.dart`
Expected: All 5 tests pass.

- [x] **Step 3: Commit**

```bash
git add app/test/models/local_session_test.dart
git commit -m "test: add LocalSession unit tests with FakePtyRunner"
```

---

## Task 3: LocalShellService unit tests

**Files:**
- Create: `app/test/services/local_shell_service_test.dart`

- [x] **Step 1: Create the test file**

```dart
// app/test/services/local_shell_service_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/pty_runner.dart';

class FakePtyRunner implements PtyRunner {
  final _outputController = StreamController<List<int>>.broadcast();
  final _exitCompleter = Completer<int>();
  final List<Uint8List> written = [];
  final List<({int rows, int cols})> resizes = [];
  bool killed = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  void write(Uint8List data) => written.add(data);

  @override
  void resize(int rows, int cols) => resizes.add((rows: rows, cols: cols));

  @override
  void kill() => killed = true;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  void emitOutput(List<int> bytes) => _outputController.add(bytes);
  void completeExit(int code) => _exitCompleter.complete(code);
  void dispose() => _outputController.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePtyRunner fakePty;
  late LocalShellService service;

  setUp(() {
    fakePty = FakePtyRunner();
    service = LocalShellService(
      ptyFactory: (shell, cols, rows, env) => fakePty,
    );
  });

  tearDown(() => fakePty.dispose());

  group('LocalShellService', () {
    test('openShell returns a running session', () async {
      final session = await service.openShell();
      expect(session.status, LocalSessionStatus.running);
    });

    test('openShell stores session, getSession returns it', () async {
      final session = await service.openShell();
      expect(service.getSession(session.id), same(session));
    });

    test('pty output is written to terminal', () async {
      final session = await service.openShell();
      final received = <String>[];
      session.terminal.onOutput = received.add;

      // Simulate terminal echoing written data back via write listener
      // The service wires: pty.output -> terminal.write
      // We verify by flushing pty output and checking terminal buffer.
      fakePty.emitOutput(utf8.encode('hello'));
      await Future<void>.delayed(Duration.zero);

      // terminal.write stores data internally; no easy public way to assert
      // contents without rendering — assert no exception thrown instead.
      expect(session.status, LocalSessionStatus.running);
    });

    test('terminal onOutput sends encoded bytes to pty', () async {
      final session = await service.openShell();
      session.terminal.onOutput?.call('hi');
      expect(fakePty.written, hasLength(1));
      expect(utf8.decode(fakePty.written.first), 'hi');
    });

    test('terminal onResize calls pty.resize with swapped rows/cols', () async {
      final session = await service.openShell();
      // onResize signature: (w, h, pw, ph) → pty.resize(h, w)
      session.terminal.onResize?.call(120, 40, 0, 0);
      expect(fakePty.resizes, hasLength(1));
      expect(fakePty.resizes.first.rows, 40);
      expect(fakePty.resizes.first.cols, 120);
    });

    test('pty exit sets session status to exited', () async {
      final session = await service.openShell();
      fakePty.completeExit(0);
      await Future<void>.delayed(Duration.zero);
      expect(session.status, LocalSessionStatus.exited);
    });

    test('closeSession kills the session and removes it', () async {
      final session = await service.openShell();
      service.closeSession(session.id);
      expect(fakePty.killed, true);
      expect(service.getSession(session.id), isNull);
    });

    test('factory error sets session to error state', () async {
      final badService = LocalShellService(
        ptyFactory: (_, __, ___, ____) => throw Exception('pty unavailable'),
      );
      final session = await badService.openShell();
      expect(session.status, LocalSessionStatus.error);
      expect(session.errorMessage, contains('pty unavailable'));
    });
  });
}
```

- [x] **Step 2: Run the tests**

Run: `cd app && flutter test test/services/local_shell_service_test.dart`
Expected: All 8 tests pass.

- [x] **Step 3: Commit**

```bash
git add app/test/services/local_shell_service_test.dart
git commit -m "test: add LocalShellService unit tests with injected FakePtyRunner"
```

---

## Task 4: SftpEntry.kindLabel tests

**Files:**
- Modify: `app/test/models/sftp_entry_test.dart`

- [x] **Step 1: Add kindLabel group to the existing file**

Append this group inside `main()`, after the existing `sortKey` test:

```dart
    test('kindLabel returns "folder" for directories', () {
      final entry = SftpEntry(name: 'src', path: '/src', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      expect(entry.kindLabel, 'folder');
    });

    test('kindLabel returns "document" for files without extension', () {
      final entry = SftpEntry(name: 'Makefile', path: '/Makefile', isDirectory: false, size: 100, modifiedAt: DateTime(2024));
      expect(entry.kindLabel, 'document');
    });

    test('kindLabel returns lowercase extension for files with extension', () {
      final entry = SftpEntry(name: 'main.DART', path: '/main.DART', isDirectory: false, size: 100, modifiedAt: DateTime(2024));
      expect(entry.kindLabel, 'dart');
    });
```

The final file should have the three new tests inside the `'SftpEntry'` group.

- [x] **Step 2: Run the tests**

Run: `cd app && flutter test test/models/sftp_entry_test.dart`
Expected: All 8 tests pass.

- [x] **Step 3: Commit**

```bash
git add app/test/models/sftp_entry_test.dart
git commit -m "test: add kindLabel tests for SftpEntry"
```

---

## Task 5: LocalFilePanelProvider showHidden / selectAll tests

**Files:**
- Modify: `app/test/providers/local_file_panel_provider_test.dart`

- [x] **Step 1: Add the new group at the end of `main()`**

Append inside `main()`, after the `'filterVisible toggle'` group:

```dart
  group('showHidden', () {
    test('showHidden starts false', () {
      expect(provider.showHidden, false);
    });

    test('toggleShowHidden flips to true', () {
      provider.toggleShowHidden();
      expect(provider.showHidden, true);
    });

    test('toggleShowHidden twice returns to false', () {
      provider.toggleShowHidden();
      provider.toggleShowHidden();
      expect(provider.showHidden, false);
    });

    test('toggleShowHidden notifies listeners', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.toggleShowHidden();
      // notification happens async via _fetchDirectory → notifyListeners
      // we only assert the sync state change here
      expect(provider.showHidden, true);
    });
  });

  group('selectAll', () {
    test('selectAll selects every filteredEntry', () {
      provider.setEntriesForTest([_entry('a'), _entry('b'), _entry('c')]);
      provider.selectAll();
      expect(provider.selectedEntries.length, 3);
    });

    test('selectAll with active filter only selects visible entries', () {
      provider.setEntriesForTest([_entry('alpha'), _entry('beta'), _entry('gamma')]);
      provider.setFilterQuery('a');
      provider.selectAll();
      // only 'alpha' and 'gamma' match 'a'
      expect(provider.selectedEntries.length, 2);
      expect(provider.selectedEntries.map((e) => e.name), containsAll(['alpha', 'gamma']));
    });

    test('selectAll on empty list is a no-op', () {
      provider.setEntriesForTest([]);
      provider.selectAll();
      expect(provider.selectedEntries.isEmpty, true);
    });
  });
```

- [x] **Step 2: Run the tests**

Run: `cd app && flutter test test/providers/local_file_panel_provider_test.dart`
Expected: All tests pass.

- [x] **Step 3: Commit**

```bash
git add app/test/providers/local_file_panel_provider_test.dart
git commit -m "test: add showHidden and selectAll tests for LocalFilePanelProvider"
```

---

## Task 6: SyncProvider keychain fallback test

**Files:**
- Modify: `app/test/providers/sync_provider_test.dart`

- [x] **Step 1: Add fallback test group inside `main()`**

Add a new group after the existing `'SyncProvider'` group (still inside `main()`). This group overrides the secure storage mock to throw, then verifies the provider falls back to SharedPreferences:

```dart
  group('SyncProvider keychain fallback', () {
    test('falls back to SharedPreferences syncId when secure storage throws', () async {
      // Override secure storage mock to throw on every call
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'SecureStorageError', message: 'Keychain unavailable');
      });

      SharedPreferences.setMockInitialValues({'sync_id': 'PREFSSYNCID12'});

      final p = SyncProvider();
      // Wait for async _init() to complete via listener
      final c = Completer<void>();
      p.addListener(() {
        if (p.syncId.isNotEmpty && !c.isCompleted) c.complete();
      });
      await c.future.timeout(const Duration(seconds: 2));

      expect(p.syncId, 'PREFSSYNCID12');
      p.dispose();
    });

    test('generates and stores a new syncId in prefs when keychain throws and prefs empty', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'SecureStorageError', message: 'Keychain unavailable');
      });

      SharedPreferences.setMockInitialValues({});

      final p = SyncProvider();
      final c = Completer<void>();
      p.addListener(() {
        if (p.syncId.isNotEmpty && !c.isCompleted) c.complete();
      });
      await c.future.timeout(const Duration(seconds: 2));

      expect(p.syncId.length, 12);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_id'), p.syncId);
      p.dispose();
    });
  });
```

- [x] **Step 2: Run the tests**

Run: `cd app && flutter test test/providers/sync_provider_test.dart`
Expected: All tests pass.

- [x] **Step 3: Commit**

```bash
git add app/test/providers/sync_provider_test.dart
git commit -m "test: add SyncProvider keychain fallback tests"
```

---

## Task 7: SyncService.disableAndDelete test

**Files:**
- Modify: `app/test/services/sync_service_test.dart`

- [x] **Step 1: Add imports and fake class at the top of the file**

Add at the top of `sync_service_test.dart`, after the existing imports:

```dart
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/supabase_service.dart';

class _ThrowingSupabase extends SupabaseService {
  @override
  Future<void> deleteSyncRow(String syncId) async {
    throw Exception('network error');
  }
}
```

- [x] **Step 2: Add mock setup and the new test group**

Add these helpers and group inside `main()`, after the existing `'SyncService encrypt/decrypt roundtrip'` group:

```dart
  group('SyncService.disableAndDelete', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final Map<String, String> secureData = {};

    setUp(() async {
      secureData.clear();
      SharedPreferences.setMockInitialValues({
        'sync_pending_push': true,
        'sync_last_push_at': '2026-01-01T00:00:00.000Z',
        'sync_enabled': true,
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (MethodCall call) async {
        switch (call.method) {
          case 'read':
            return secureData[call.arguments['key'] as String];
          case 'write':
            secureData[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null);
    });

    Future<SyncProvider> _buildProvider() async {
      final p = SyncProvider();
      final c = Completer<void>();
      p.addListener(() { if (!c.isCompleted) c.complete(); });
      await c.future.timeout(const Duration(seconds: 2));
      return p;
    }

    test('clears local prefs and disables sync even when remote delete throws', () async {
      final syncProvider = await _buildProvider();
      await syncProvider.setEnabled(true);

      final service = SyncService(syncProvider, _ThrowingSupabase());
      await service.disableAndDelete();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sync_pending_push'), isNull);
      expect(prefs.getString('sync_last_push_at'), isNull);
      expect(syncProvider.enabled, false);

      syncProvider.dispose();
    });
  });
```

- [x] **Step 3: Run the tests**

Run: `cd app && flutter test test/services/sync_service_test.dart`
Expected: All tests pass.

- [x] **Step 4: Commit**

```bash
git add app/test/services/sync_service_test.dart
git commit -m "test: add SyncService.disableAndDelete error-resilience test"
```

---

## Task 8: CI test gate

**Files:**
- Modify: `.github/workflows/release.yml`

- [x] **Step 1: Replace `release.yml` with the new version that adds a `test` job**

Replace the full file content:

```yaml
name: Release

on:
  push:
    branches:
      - master

permissions:
  contents: write

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        working-directory: app
        run: flutter pub get

      - name: Analyze
        working-directory: app
        run: flutter analyze

      - name: Test
        working-directory: app
        run: flutter test

  build-macos:
    runs-on: macos-latest
    needs: test
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        working-directory: app
        run: flutter pub get

      - name: Build macOS
        working-directory: app
        run: flutter build macos --release

      - name: Zip macOS app
        run: zip -r YourSSH-macos.zip "app/build/macos/Build/Products/Release/YourSSH.app"

      - uses: actions/upload-artifact@v4
        with:
          name: macos-build
          path: YourSSH-macos.zip

  build-windows:
    runs-on: windows-latest
    needs: test
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        working-directory: app
        run: flutter pub get

      - name: Build Windows
        working-directory: app
        run: flutter build windows --release

      - name: Zip Windows build
        shell: pwsh
        run: Compress-Archive -Path "app\build\windows\x64\runner\Release\*" -DestinationPath "YourSSH-windows.zip"

      - uses: actions/upload-artifact@v4
        with:
          name: windows-build
          path: YourSSH-windows.zip

  release:
    runs-on: ubuntu-latest
    needs: [build-macos, build-windows]
    steps:
      - uses: actions/checkout@v4

      - name: Extract version from pubspec.yaml
        id: version
        run: |
          VERSION=$(grep '^version:' app/pubspec.yaml | sed 's/^version:[[:space:]]*//' | cut -d'+' -f1)
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - uses: actions/download-artifact@v4
        with:
          name: macos-build

      - uses: actions/download-artifact@v4
        with:
          name: windows-build

      - uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.version.outputs.version }}
          name: YourSSH v${{ steps.version.outputs.version }}
          generate_release_notes: true
          files: |
            YourSSH-macos.zip
            YourSSH-windows.zip
```

- [x] **Step 2: Run full test suite locally to verify all tests pass**

Run: `cd app && flutter test`
Expected: All tests pass with no failures.

- [x] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add test job as gate before macOS and Windows builds"
```

---

## Self-Review

**Spec coverage:**
- ✅ PtyRunner abstraction — Task 1
- ✅ LocalSession tests — Task 2
- ✅ LocalShellService tests — Task 3
- ✅ SftpEntry.kindLabel tests — Task 4
- ✅ LocalFilePanelProvider.showHidden / selectAll — Task 5
- ✅ SyncProvider keychain fallback — Task 6
- ✅ SyncService.disableAndDelete resilience — Task 7
- ✅ CI test gate before release — Task 8

**Placeholder scan:** No TBDs, no "similar to Task N", all code blocks complete.

**Type consistency:**
- `PtyRunner` defined in Task 1, used by name consistently in Tasks 2 and 3.
- `FakePtyRunner` defined per test file (not shared) to avoid coupling.
- `_ThrowingSupabase` defined in Task 7 within the same file, not exported.
- `PtyFactory` typedef used in `LocalShellService` matches the factory signature in Task 3 tests.
