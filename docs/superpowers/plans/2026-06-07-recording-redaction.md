# Recording Redaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mask secrets in terminal output before it is written to `.cast` recordings, via a line buffer in `RecordingService` reusing `AuditRedactor` unchanged, toggleable globally and per-host (both default on).

**Architecture:** `RecordingService.startRecording` gains `redact: bool`. When on, `writeOutput` coalesces chunks in a per-recording `StringBuffer`, splits at the **last** newline, redacts the complete portion with `AuditRedactor.redact()`, and writes it as one event; a start-once (non-debounced) `flushDelay` timer (default 500 ms) bounds latency for TUI output without newlines. `RecordingProvider` samples a `redactionPolicy` callback once at start; `main.dart` wires it to `SettingsProvider.recordingRedactionEnabled && Host.recordingRedaction`.

**Tech Stack:** Dart `Timer`/`StringBuffer`, existing `AuditRedactor`, provider, SharedPreferences, existing recording test patterns (temp dirs + short real delays — **not** fakeAsync: `startRecording` does real file IO that never completes inside a fake zone).

**Spec:** `docs/superpowers/specs/2026-06-07-recording-redaction-design.md`

---

## File map

| File | Change |
|---|---|
| `app/lib/models/host.dart` | `recordingRedaction` bool (default true) + JSON + copyWith |
| `app/lib/providers/settings_provider.dart` | `recordingRedactionEnabled` field + load + save |
| `app/lib/services/recording_service.dart` | `flushDelay` ctor param; `redact:` on startRecording; line buffer + timer + stop-flush |
| `app/lib/providers/recording_provider.dart` | `redactionPolicy` callback → `redact:` pass-through |
| `app/lib/widgets/settings_screen.dart` | switch row in the Recording section |
| `app/lib/widgets/host_detail_panel.dart` | `_recordingRedaction` state + switch in SESSION card + `_save` |
| `app/lib/main.dart` | wire `redactionPolicy` |
| Tests | `host_test.dart` (add), `settings_provider_redaction_test.dart` (new), `recording_service_test.dart` (add group), `recording_provider_test.dart` (add), `host_detail_panel_recording_test.dart` (new) |
| `CLAUDE.md` | document the feature |

Facts locked during exploration: `RecordingService` is 87 lines, `_ActiveRecording` at the bottom holds `sink`/`stopwatch`/`filePath`; `writeOutput` writes `[elapsed,'o',data]` per chunk; `stopRecording` removes from `_active` **before** flushing the sink. `RecordingProvider.startRecording(TerminalSession)` calls the service at recording_provider.dart:60. `main.dart:204` wires `recordingStart`; main.dart does **not** yet import `models/ssh_session.dart`. `settings_screen.dart` has `final settings = context.watch<SettingsProvider>()` in scope (line 37) and the Recording `_Section` at line 151. Host panel SESSION card with the `_autoRecord` SwitchListTile is at host_detail_panel.dart:495-510. `AuditRedactor.kMask == '[REDACTED]'`. Existing recording tests use real temp dirs and `Future.delayed`, and note Windows file-locking: always `stopRecording` before reading the file.

All commands run from `app/`.

---

### Task 1: Host model — `recordingRedaction`

**Files:**
- Modify: `app/lib/models/host.dart`
- Test: `app/test/models/host_test.dart` (add)

- [ ] **Step 1: Write the failing tests**

Add to the main group in `app/test/models/host_test.dart`:

```dart
    test('recordingRedaction round-trips and defaults to true', () {
      final h = Host(label: 'x', host: 'y', username: 'z');
      expect(h.recordingRedaction, isTrue);
      expect(Host.fromJson(h.toJson()).recordingRedaction, isTrue);

      final off = Host(
          label: 'x', host: 'y', username: 'z', recordingRedaction: false);
      expect(Host.fromJson(off.toJson()).recordingRedaction, isFalse);
    });

    test('recordingRedaction missing in JSON defaults to true', () {
      final decoded = Host.fromJson({'host': 'y', 'username': 'z'});
      expect(decoded.recordingRedaction, isTrue);
    });

    test('copyWith keeps and overrides recordingRedaction', () {
      final h = Host(
          label: 'x', host: 'y', username: 'z', recordingRedaction: false);
      expect(h.copyWith(label: 'new').recordingRedaction, isFalse);
      expect(h.copyWith(recordingRedaction: true).recordingRedaction, isTrue);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/host_test.dart`
Expected: FAIL — `recordingRedaction` not defined.

- [ ] **Step 3: Implement**

In `host.dart`, mirror `shellIntegration` exactly:

Field (after `bool autoRecord;`):

```dart
  /// Mask secrets (AuditRedactor patterns) in this host's recordings.
  /// Effective only while the global Settings toggle is also on.
  bool recordingRedaction;
```

Constructor (after `this.autoRecord = false,`): `this.recordingRedaction = true,`

`toJson` (after `'autoRecord': autoRecord,`): `'recordingRedaction': recordingRedaction,`

`fromJson` (after the `autoRecord` line):
`recordingRedaction: (json['recordingRedaction'] as bool?) ?? true,`

`copyWith` — param `bool? recordingRedaction,` and forwarding
`recordingRedaction: recordingRedaction ?? this.recordingRedaction,`
(place both next to the `autoRecord` lines).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/models/host_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_test.dart
git commit -m "feat: Host.recordingRedaction flag (default on)"
```

---

### Task 2: SettingsProvider — `recordingRedactionEnabled`

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Test: `app/test/providers/settings_provider_redaction_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `app/test/providers/settings_provider_redaction_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordingRedactionEnabled defaults true, persists via save', () async {
    SharedPreferences.setMockInitialValues({});
    final p = SettingsProvider();
    await Future<void>.delayed(Duration.zero); // let _load() finish
    expect(p.recordingRedactionEnabled, isTrue);

    await p.save(recordingRedactionEnabled: false);
    expect(p.recordingRedactionEnabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('recordingRedactionEnabled'), isFalse);
  });

  test('recordingRedactionEnabled loads persisted false', () async {
    SharedPreferences.setMockInitialValues(
        {'recordingRedactionEnabled': false});
    final p = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(p.recordingRedactionEnabled, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/settings_provider_redaction_test.dart`
Expected: FAIL — `recordingRedactionEnabled` not defined.

- [ ] **Step 3: Implement**

In `settings_provider.dart`, mirror `shellIntegrationEnabled` in all four places:

- Field (after `bool shellIntegrationEnabled = true;`):
  `bool recordingRedactionEnabled = true;`
- `_load()` (after the `shellIntegrationEnabled` line):
  `recordingRedactionEnabled = prefs.getBool('recordingRedactionEnabled') ?? true;`
- `save(...)` param: `bool? recordingRedactionEnabled,`
- `save(...)` body assignment:
  `if (recordingRedactionEnabled != null) this.recordingRedactionEnabled = recordingRedactionEnabled;`
  and persist:
  `await prefs.setBool('recordingRedactionEnabled', this.recordingRedactionEnabled);`

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/providers/settings_provider_redaction_test.dart test/providers/settings_provider_shell_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/providers/settings_provider_redaction_test.dart
git commit -m "feat: global recordingRedactionEnabled setting (default on)"
```

---

### Task 3: RecordingService — line-buffered redaction

**Files:**
- Modify: `app/lib/services/recording_service.dart`
- Test: `app/test/services/recording_service_test.dart` (add group)

- [ ] **Step 1: Write the failing tests**

Add to `app/test/services/recording_service_test.dart` (inside `main()`, after the existing tests; `service`/`tmpDir` come from the existing `setUp`):

```dart
  group('redaction', () {
    // Events only (header line skipped). Always stopRecording before calling
    // this — Windows locks the open file.
    Future<List<String>> eventsOf(String path) async =>
        (await File(path).readAsLines()).skip(1).toList();

    Future<void> start(RecordingService s, String path,
            {bool redact = true}) =>
        s.startRecording('s1',
            filePath: path, width: 80, height: 24, title: 't', redact: redact);

    test('secret split across two chunks is masked', () async {
      final path = '${tmpDir.path}/r1.cast';
      await start(service, path);
      service.writeOutput('s1', 'export PGPASS');
      service.writeOutput('s1', 'WORD=hunter2\n');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, contains('[REDACTED]'));
      expect(events.single, isNot(contains('hunter2')));
    });

    test('keystroke echo (one char per chunk) is masked', () async {
      final path = '${tmpDir.path}/r2.cast';
      await start(service, path);
      for (final ch in 'token=abc123\n'.split('')) {
        service.writeOutput('s1', ch);
      }
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, isNot(contains('abc123')));
    });

    test('multi-newline chunk written as one redacted event', () async {
      final path = '${tmpDir.path}/r3.cast';
      await start(service, path);
      service.writeOutput('s1', 'a\npassword=x\nb\n');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, isNot(contains('password=x')));
    });

    test('partial line flushes redacted after flushDelay', () async {
      final s = RecordingService(flushDelay: const Duration(milliseconds: 30));
      final path = '${tmpDir.path}/r4.cast';
      await start(s, path);
      s.writeOutput('s1', 'secret=abc'); // no newline
      await Future<void>.delayed(const Duration(milliseconds: 120));
      s.writeOutput('s1', 'later\n'); // separate event ⇒ timer fired earlier
      await s.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(2));
      expect(events[0], contains('[REDACTED]'));
      expect(events[1], contains('later'));
      // Timestamps stay non-decreasing across buffered flushes.
      final t0 = (jsonDecode(events[0]) as List).first as num;
      final t1 = (jsonDecode(events[1]) as List).first as num;
      expect(t1, greaterThanOrEqualTo(t0));
    });

    test('stopRecording flushes a pending partial line', () async {
      final path = '${tmpDir.path}/r5.cast';
      await start(service, path);
      service.writeOutput('s1', 'api_key=tail-no-newline');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, isNot(contains('tail-no-newline')));
    });

    test('redact:false keeps one raw event per chunk (legacy path)', () async {
      final path = '${tmpDir.path}/r6.cast';
      await start(service, path, redact: false);
      service.writeOutput('s1', 'password=plain');
      service.writeOutput('s1', 'second\n');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(2));
      expect(events[0], contains('password=plain'));
    });
  });
```

Add the import at the top of the test file: `import 'dart:convert';`

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/recording_service_test.dart`
Expected: FAIL — no `redact`/`flushDelay` named parameters.

- [ ] **Step 3: Implement**

In `recording_service.dart` (it already imports `dart:async`, `dart:convert`, `dart:io`):

Add import: `import 'audit_redactor.dart';`

Constructor + field on `RecordingService`:

```dart
  RecordingService({this.flushDelay = const Duration(milliseconds: 500)});

  /// Max time a redacted recording's partial line (no newline yet) sits
  /// buffered before being flushed — bounds latency and buffer growth for
  /// TUI output that rarely prints newlines.
  final Duration flushDelay;
```

`startRecording` — add `bool redact = false,` to the named params and pass it
through:

```dart
      _active[sessionId] = _ActiveRecording(
        sink: sink,
        stopwatch: Stopwatch()..start(),
        filePath: filePath,
        redact: redact,
      );
```

Replace `writeOutput` and add the two helpers:

```dart
  void writeOutput(String sessionId, String data) {
    final rec = _active[sessionId];
    if (rec == null) return;
    if (!rec.redact) {
      _writeEvent(rec, data); // legacy path: one raw event per chunk
      return;
    }
    rec.pending.write(data);
    final buffered = rec.pending.toString();
    // Split at the LAST newline: the complete portion is redacted and
    // written as one event; the partial tail stays buffered so a secret
    // straddling chunks can still join up before matching.
    final lastNl = buffered.lastIndexOf('\n');
    if (lastNl >= 0) {
      rec.pending.clear();
      rec.pending.write(buffered.substring(lastNl + 1));
      _writeEvent(rec, AuditRedactor.redact(buffered.substring(0, lastNl + 1)));
    }
    if (rec.pending.isEmpty) {
      rec.flushTimer?.cancel();
      rec.flushTimer = null;
    } else {
      // Start-once, no debounce: continuous TUI output without newlines
      // must still flush at most flushDelay after the first buffered byte.
      rec.flushTimer ??= Timer(flushDelay, () => _flushPending(sessionId));
    }
  }

  void _writeEvent(_ActiveRecording rec, String data) {
    final elapsed = rec.stopwatch.elapsedMicroseconds / 1000000.0;
    rec.sink.writeln(jsonEncode([elapsed, 'o', data]));
  }

  void _flushPending(String sessionId) {
    final rec = _active[sessionId];
    if (rec == null) return; // stopped while the timer was in flight
    rec.flushTimer = null;
    if (rec.pending.isEmpty) return;
    final text = rec.pending.toString();
    rec.pending.clear();
    _writeEvent(rec, AuditRedactor.redact(text));
  }
```

`stopRecording` — flush the buffered tail before closing (rec is already out
of `_active`, so inline rather than via `_flushPending`):

```dart
  Future<String?> stopRecording(String sessionId) async {
    final rec = _active.remove(sessionId);
    if (rec == null) return null;
    rec.flushTimer?.cancel();
    rec.flushTimer = null;
    if (rec.pending.isNotEmpty) {
      _writeEvent(rec, AuditRedactor.redact(rec.pending.toString()));
      rec.pending.clear();
    }
    rec.stopwatch.stop();
    // Notify as soon as the recording leaves _active — the sink flush below
    // is async and the UI must not show a red REC indicator meanwhile.
    onRecordingStopped?.call(sessionId);
    await rec.sink.flush();
    await rec.sink.close();
    return rec.filePath;
  }
```

`_ActiveRecording` — add the redaction state:

```dart
class _ActiveRecording {
  final IOSink sink;
  final Stopwatch stopwatch;
  final String filePath;
  final bool redact;
  final StringBuffer pending = StringBuffer();
  Timer? flushTimer;

  _ActiveRecording({
    required this.sink,
    required this.stopwatch,
    required this.filePath,
    required this.redact,
  });
}
```

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/services/recording_service_test.dart`
Expected: PASS — including all pre-existing tests (legacy path untouched).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/recording_service.dart app/test/services/recording_service_test.dart
git commit -m "feat: line-buffered secret redaction in RecordingService"
```

---

### Task 4: RecordingProvider — redactionPolicy

**Files:**
- Modify: `app/lib/providers/recording_provider.dart`
- Test: `app/test/providers/recording_provider_test.dart` (add)

- [ ] **Step 1: Write the failing tests**

Add to `app/test/providers/recording_provider_test.dart` (top level, after the
existing fakes/imports — `LocalSession`, `Terminal`, `RecordingService` are
already imported there):

```dart
class _CapturingService extends RecordingService {
  bool? capturedRedact;

  @override
  Future<void> startRecording(
    String sessionId, {
    required String filePath,
    required int width,
    required int height,
    required String title,
    bool redact = false,
  }) async {
    capturedRedact = redact;
  }
}
```

and the tests inside `main()`:

```dart
  test('redactionPolicy result is passed to the service', () async {
    final service = _CapturingService();
    final provider = RecordingProvider(service, getPath: () => tmpDir.path);
    provider.redactionPolicy = (_) => true;

    await provider.startRecording(LocalSession(terminal: Terminal()));
    expect(service.capturedRedact, isTrue);
  });

  test('null redactionPolicy records without redaction', () async {
    final service = _CapturingService();
    final provider = RecordingProvider(service, getPath: () => tmpDir.path);

    await provider.startRecording(LocalSession(terminal: Terminal()));
    expect(service.capturedRedact, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/recording_provider_test.dart`
Expected: FAIL — `redactionPolicy` not defined.

- [ ] **Step 3: Implement**

In `recording_provider.dart`, add the field next to `onStartFailed`:

```dart
  /// Decides whether a session's recording is redacted; sampled once at
  /// start time (mid-session toggle changes apply to the next recording).
  /// Wired in main.dart from SettingsProvider + Host. Null (tests) = off.
  bool Function(TerminalSession session)? redactionPolicy;
```

and in `startRecording`, extend the service call:

```dart
      await _service.startRecording(
        session.id,
        filePath: filePath,
        width: session.terminal.viewWidth,
        height: session.terminal.viewHeight,
        title: title,
        redact: redactionPolicy?.call(session) ?? false,
      );
```

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/providers/recording_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/recording_provider.dart app/test/providers/recording_provider_test.dart
git commit -m "feat: RecordingProvider redactionPolicy hook"
```

---

### Task 5: UI toggles + main.dart wiring

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart` (Recording section, ~line 151)
- Modify: `app/lib/widgets/host_detail_panel.dart` (SESSION card, ~line 495)
- Modify: `app/lib/main.dart` (~line 204)
- Test: `app/test/widgets/host_detail_panel_recording_test.dart` (new)

- [ ] **Step 1: Write the failing panel test**

Create `app/test/widgets/host_detail_panel_recording_test.dart` (same harness
as `host_detail_panel_chain_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HostDetailPanel(
              existing: existing,
              agentProbe: () async => const AgentProbeSystem(1),
              onClose: () {},
              onSave: (host, _) async => saved = host,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Host target({bool recordingRedaction = true}) => Host(
        id: 'target-id',
        label: 'target',
        host: '1.2.3.4',
        username: 'root',
        recordingRedaction: recordingRedaction,
      );

  testWidgets('toggle off saves recordingRedaction=false', (tester) async {
    await pumpPanel(tester, existing: target());

    final toggle = find.text('Redact secrets in recordings');
    expect(toggle, findsOneWidget);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.recordingRedaction, isFalse);
  });

  testWidgets('existing false loads into the toggle and survives save',
      (tester) async {
    await pumpPanel(tester, existing: target(recordingRedaction: false));

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved!.recordingRedaction, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/host_detail_panel_recording_test.dart`
Expected: FAIL — the toggle text doesn't exist yet.

- [ ] **Step 3: Implement the panel toggle**

In `host_detail_panel.dart`:

- State field (next to `bool _autoRecord = false;`):
  `bool _recordingRedaction = true;`
- `initState` (next to the `_autoRecord` line):
  `_recordingRedaction = h?.recordingRedaction ?? true;`
- `_save`'s `Host(...)` construction (after `autoRecord: _autoRecord,`):
  `recordingRedaction: _recordingRedaction,`
  (the `_test()` throwaway Host doesn't need it — redaction is irrelevant to
  testConnection.)
- SESSION `_Card` — insert directly after the `Auto-record sessions`
  SwitchListTile (line ~510):

```dart
                    SwitchListTile(
                      value: _recordingRedaction,
                      onChanged: (v) =>
                          setState(() => _recordingRedaction = v),
                      title: const Text(
                        'Redact secrets in recordings',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Mask passwords/tokens before writing .cast',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
```

- [ ] **Step 4: Implement the Settings switch**

In `settings_screen.dart`, append to the Recording `_Section`'s `children`
(after the recording-path `Consumer`, before the closing `]),` at ~line 193;
`settings` is already in scope from line 37):

```dart
                  SwitchListTile(
                    title: const Text('Redact secrets in recordings', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Mask passwords/tokens (AuditRedactor patterns) before writing .cast — replay timing becomes per-line; per-host opt-out in the host panel', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.recordingRedactionEnabled,
                    onChanged: (v) => context
                        .read<SettingsProvider>()
                        .save(recordingRedactionEnabled: v),
                  ),
```

- [ ] **Step 5: Wire the policy in main.dart**

Add the import (main.dart does not import it yet):

```dart
import 'models/ssh_session.dart';
```

After line 204 (`_sessionProvider.recordingStart = ...`):

```dart
    // Effective redaction = global AND per-host; local shells (no Host)
    // follow the global toggle alone. Sampled once at recording start.
    _recordingProvider.redactionPolicy = (s) =>
        _settingsProvider.recordingRedactionEnabled &&
        (s is! SshSession || s.host.recordingRedaction);
```

- [ ] **Step 6: Run tests**

Run: `cd app && flutter test test/widgets/host_detail_panel_recording_test.dart test/widgets/host_detail_panel_chain_test.dart && flutter analyze`
Expected: PASS, 0 analyze issues.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/settings_screen.dart app/lib/widgets/host_detail_panel.dart app/lib/main.dart app/test/widgets/host_detail_panel_recording_test.dart
git commit -m "feat: recording redaction toggles (Settings + per-host) wired to policy"
```

---

### Task 6: Full verification + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full analyze + test**

Run: `cd app && flutter analyze && flutter test`
Expected: 0 issues, all tests pass.

- [ ] **Step 2: Update CLAUDE.md**

- `RecordingService` bullet: append "; when `redact:` is on (effective =
  `SettingsProvider.recordingRedactionEnabled` AND `Host.recordingRedaction`,
  both default true; sampled once at start via
  `RecordingProvider.redactionPolicy` wired in main.dart), output is
  line-buffered (split at the last newline, start-once `flushDelay` timer,
  default 500 ms, stop flushes the tail) and passed through
  `AuditRedactor.redact()` before writing — coalesces events per line, which
  also strips keystroke timing; ANSI escapes inside a secret defeat the
  regexes (defense-in-depth, not a guarantee)".
- `Host` model bullet: add `recordingRedaction` to the listed per-host flags.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: recording redaction in CLAUDE.md"
```

- [ ] **Step 4: Roadmap**

Leave the roadmap update to the `/yourssh-roadmap` skill after merge (it
moves "Recording redaction" from P1 to shipped).

---

## Self-review notes (already applied)

- **Spec coverage:** toggle model → T1/T2/T5; line buffer + timer semantics +
  stop-flush → T3; policy sampling at start → T4/T5; Settings/panel UI → T5;
  known limitations → CLAUDE.md text in T6. The spec's `fakeAsync` testing
  note was replaced with short real delays — `startRecording` awaits real
  file IO, which never completes inside a fake zone; this matches the
  existing recording tests' style.
- **Type consistency:** `redact` (named param, default false) flows
  service ← provider ← policy; `flushDelay` is a `RecordingService`
  constructor param used by T3's timer test; `_CapturingService` (T4)
  overrides the exact T3 signature.
- **Known risks:** `_flushPending` runs from a real `Timer` — it re-looks-up
  `_active` so a stop racing the timer is a no-op, and `stopRecording`
  cancels the timer before flushing inline. `redact:false` writes are
  byte-identical to today (pre-existing tests in T3 Step 4 prove it).
