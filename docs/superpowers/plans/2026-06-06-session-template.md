# Session Template / Per-host Preset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-host session presets — working dir, env vars, startup snippet (delivered via the existing invisible-injection handshake), plus per-host theme/font/TERM/tmux overrides falling back to globals.

**Architecture:** Extend `Host` with 8 nullable/empty-default fields. The hidden setup (cd/export) rides the existing two-phase invisible handshake in `SshService.openShell` (readiness → bootstrap → RDY → payload → DONE); the startup snippet is typed visibly when DONE is seen. TERM/tmux resolve per-host-first in `SessionProvider._doConnect`; theme/font resolve in `terminal_view.dart` via a pure resolver with fresh-host lookup.

**Tech Stack:** Flutter/Dart, existing `ShellIntegrationService` + `InjectionGate` machinery, no new dependencies.

**Spec:** `docs/superpowers/specs/2026-06-06-session-template-design.md`

---

## File map

| File | Change |
|---|---|
| `app/lib/models/host.dart` | 8 new fields + `hasTemplateSetup` + JSON + copyWith |
| `app/lib/services/shell_integration_service.dart` | `shQuote`, `isValidEnvKey`, parameterized `buildPayloadLine` |
| `app/lib/providers/shell_integration_provider.dart` | delegation passes new params through |
| `app/lib/services/ssh_service.dart` | `openShell`: handshake gating (`injectOn`), payload args, snippet send |
| `app/lib/providers/session_provider.dart` | per-host TERM/tmux resolution in `_doConnect` |
| `app/lib/util/terminal_appearance.dart` | **new** — pure appearance resolver |
| `app/lib/widgets/terminal_view.dart` | use resolver instead of raw settings reads |
| `app/lib/widgets/host_detail_panel.dart` | SESSION TEMPLATE section |
| Tests | `app/test/models/host_session_template_test.dart` (new), `app/test/services/session_template_payload_test.dart` (new), `app/test/services/ssh_service_open_shell_test.dart` (extend), `app/test/providers/session_provider_template_test.dart` (new), `app/test/util/terminal_appearance_test.dart` (new), `app/test/widgets/host_detail_panel_template_test.dart` (new) |

All test/build commands run from `app/`: `cd app`.

---

### Task 1: Host model — template fields

**Files:**
- Modify: `app/lib/models/host.dart`
- Test: `app/test/models/host_session_template_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `app/test/models/host_session_template_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

Host _minimal() => Host(label: 'a', host: 'a.com', username: 'u');

Host _full() => Host(
      label: 'a',
      host: 'a.com',
      username: 'u',
      workingDir: '/srv/app',
      envVars: {'FOO': 'bar'},
      startupSnippet: 'htop',
      terminalThemeId: 'Dracula',
      fontFamily: 'MesloLGS NF',
      fontSize: 15,
      termType: 'vt100',
      tmuxOverride: true,
    );

void main() {
  test('defaults: no template, no overrides, hasTemplateSetup false', () {
    final h = _minimal();
    expect(h.workingDir, isNull);
    expect(h.envVars, isEmpty);
    expect(h.startupSnippet, isNull);
    expect(h.terminalThemeId, isNull);
    expect(h.fontFamily, isNull);
    expect(h.fontSize, isNull);
    expect(h.termType, isNull);
    expect(h.tmuxOverride, isNull);
    expect(h.hasTemplateSetup, isFalse);
  });

  test('JSON round-trip preserves all template fields', () {
    final r = Host.fromJson(_full().toJson());
    expect(r.workingDir, '/srv/app');
    expect(r.envVars, {'FOO': 'bar'});
    expect(r.startupSnippet, 'htop');
    expect(r.terminalThemeId, 'Dracula');
    expect(r.fontFamily, 'MesloLGS NF');
    expect(r.fontSize, 15.0);
    expect(r.termType, 'vt100');
    expect(r.tmuxOverride, isTrue);
  });

  test('fromJson tolerates missing fields (old payload)', () {
    final h = Host.fromJson({'host': 'a.com', 'username': 'u'});
    expect(h.envVars, isEmpty);
    expect(h.workingDir, isNull);
    expect(h.tmuxOverride, isNull);
    expect(h.hasTemplateSetup, isFalse);
  });

  test('fromJson tolerates malformed envVars (not a map)', () {
    final h = Host.fromJson(
        {'host': 'a.com', 'username': 'u', 'envVars': 'garbage'});
    expect(h.envVars, isEmpty);
  });

  test('fromJson accepts int fontSize (JSON has no double/int distinction)',
      () {
    final h =
        Host.fromJson({'host': 'a.com', 'username': 'u', 'fontSize': 14});
    expect(h.fontSize, 14.0);
  });

  test('hasTemplateSetup true for each of dir / env / snippet alone', () {
    expect(
        Host(label: 'a', host: 'a.com', username: 'u', workingDir: '/x')
            .hasTemplateSetup,
        isTrue);
    expect(
        Host(label: 'a', host: 'a.com', username: 'u', envVars: {'A': '1'})
            .hasTemplateSetup,
        isTrue);
    expect(
        Host(label: 'a', host: 'a.com', username: 'u', startupSnippet: 'ls')
            .hasTemplateSetup,
        isTrue);
  });

  test('copyWith keeps template fields by default, clears via explicit null',
      () {
    final h = _full();
    final same = h.copyWith(label: 'x');
    expect(same.workingDir, '/srv/app');
    expect(same.envVars, {'FOO': 'bar'});
    expect(same.startupSnippet, 'htop');
    expect(same.terminalThemeId, 'Dracula');
    expect(same.fontFamily, 'MesloLGS NF');
    expect(same.fontSize, 15.0);
    expect(same.termType, 'vt100');
    expect(same.tmuxOverride, isTrue);

    final cleared = h.copyWith(
      workingDir: null,
      startupSnippet: null,
      terminalThemeId: null,
      fontFamily: null,
      fontSize: null,
      termType: null,
      tmuxOverride: null,
    );
    expect(cleared.workingDir, isNull);
    expect(cleared.startupSnippet, isNull);
    expect(cleared.terminalThemeId, isNull);
    expect(cleared.fontFamily, isNull);
    expect(cleared.fontSize, isNull);
    expect(cleared.termType, isNull);
    expect(cleared.tmuxOverride, isNull);
  });

  test('envVars is an owned growable copy', () {
    final h = Host(
        label: 'a', host: 'a.com', username: 'u', envVars: const {'A': '1'});
    expect(() => h.envVars['B'] = '2', returnsNormally);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/host_session_template_test.dart`
Expected: FAIL — compile errors, `workingDir` etc. not defined on `Host`.

- [ ] **Step 3: Implement the model fields**

In `app/lib/models/host.dart`:

Field declarations (after `String? sftpServerCommand;`):

```dart
  // ── Session template (per-host preset) ──────────────────────────────
  // All null/empty = no override; see
  // docs/superpowers/specs/2026-06-06-session-template-design.md.
  String? workingDir;
  Map<String, String> envVars;
  String? startupSnippet;
  String? terminalThemeId;
  String? fontFamily;
  double? fontSize;
  String? termType;
  bool? tmuxOverride;
```

Constructor — add named params and own the map (same reason as `tags`):

```dart
    this.workingDir,
    Map<String, String> envVars = const {},
    this.startupSnippet,
    this.terminalThemeId,
    this.fontFamily,
    this.fontSize,
    this.termType,
    this.tmuxOverride,
  })  : id = id ?? const Uuid().v4(),
        // Always own a growable copy so callers can `tags.add(...)`
        // without hitting `Unsupported operation` on the shared `const []`.
        tags = List.of(tags),
        envVars = Map.of(envVars),
        createdAt = createdAt ?? DateTime.now();
```

Getter (after the constructor):

```dart
  /// Whether connect-time template work exists. Drives the invisible
  /// handshake when shell integration is off — the snippet needs the
  /// handshake too, since DONE is its send trigger.
  bool get hasTemplateSetup =>
      workingDir != null || envVars.isNotEmpty || startupSnippet != null;
```

`toJson` — add:

```dart
        'workingDir': workingDir,
        'envVars': envVars,
        'startupSnippet': startupSnippet,
        'terminalThemeId': terminalThemeId,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'termType': termType,
        'tmuxOverride': tmuxOverride,
```

`fromJson` — add a local parser next to `parseSftpMode()`:

```dart
    Map<String, String> parseEnvVars() {
      final raw = json['envVars'];
      // Malformed/forward-compat values degrade to empty rather than
      // throwing: a single bad host in a sync payload must not abort
      // loading the whole list.
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
```

and in the returned `Host(...)`:

```dart
      workingDir: json['workingDir'] as String?,
      envVars: parseEnvVars(),
      startupSnippet: json['startupSnippet'] as String?,
      terminalThemeId: json['terminalThemeId'] as String?,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      termType: json['termType'] as String?,
      tmuxOverride: json['tmuxOverride'] as bool?,
```

`copyWith` — add params (nullables use the existing `_Unset` sentinel):

```dart
    Object? workingDir = const _Unset(),
    Map<String, String>? envVars,
    Object? startupSnippet = const _Unset(),
    Object? terminalThemeId = const _Unset(),
    Object? fontFamily = const _Unset(),
    Object? fontSize = const _Unset(),
    Object? termType = const _Unset(),
    Object? tmuxOverride = const _Unset(),
```

and forwarding:

```dart
        workingDir: workingDir is _Unset ? this.workingDir : workingDir as String?,
        envVars: envVars ?? this.envVars,
        startupSnippet: startupSnippet is _Unset
            ? this.startupSnippet
            : startupSnippet as String?,
        terminalThemeId: terminalThemeId is _Unset
            ? this.terminalThemeId
            : terminalThemeId as String?,
        fontFamily: fontFamily is _Unset ? this.fontFamily : fontFamily as String?,
        fontSize: fontSize is _Unset ? this.fontSize : fontSize as double?,
        termType: termType is _Unset ? this.termType : termType as String?,
        tmuxOverride:
            tmuxOverride is _Unset ? this.tmuxOverride : tmuxOverride as bool?,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/models/`
Expected: PASS (new file + all existing host tests stay green).

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_session_template_test.dart
git commit -m "feat: session-template fields on Host model"
```

---

### Task 2: Payload builder — shQuote, isValidEnvKey, parameterized buildPayloadLine

**Files:**
- Modify: `app/lib/services/shell_integration_service.dart`
- Modify: `app/lib/providers/shell_integration_provider.dart:19-20`
- Test: `app/test/services/session_template_payload_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `app/test/services/session_template_payload_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/shell_integration_service.dart';

void main() {
  final svc = ShellIntegrationService();

  group('shQuote', () {
    test('wraps in single quotes', () {
      expect(ShellIntegrationService.shQuote('abc'), "'abc'");
    });

    test('escapes embedded single quotes', () {
      expect(ShellIntegrationService.shQuote("it's"), r"'it'\''s'");
    });

    test('strips control chars — payload must stay one line', () {
      expect(ShellIntegrationService.shQuote('a\nb\tc'), "'abc'");
    });
  });

  group('isValidEnvKey', () {
    test('accepts POSIX names', () {
      for (final k in ['FOO', '_FOO', 'F00_BAR', 'a']) {
        expect(ShellIntegrationService.isValidEnvKey(k), isTrue, reason: k);
      }
    });

    test('rejects invalid names', () {
      for (final k in ['1FOO', 'FOO-BAR', '', 'FOO BAR', 'FOO=']) {
        expect(ShellIntegrationService.isValidEnvKey(k), isFalse, reason: k);
      }
    });
  });

  group('buildPayloadLine', () {
    test('defaults are byte-identical to the legacy installer payload', () {
      // No template → existing shell-integration behavior must not change.
      expect(svc.buildPayloadLine(workingDir: null, envVars: const {}),
          svc.buildPayloadLine());
      expect(svc.buildPayloadLine(), contains('__yourssh_si'));
      expect(svc.buildPayloadLine(), contains(r"printf '__YS_%s__\n' DONE"));
    });

    test('orders installer → cd → exports → DONE → warning', () {
      final line = svc.buildPayloadLine(
          workingDir: '/srv/app', envVars: {'FOO': 'a', 'BAR': 'b'});
      final idx = [
        line.indexOf('__yourssh_si'),
        line.indexOf("cd -- '/srv/app' 2>/dev/null"),
        line.indexOf("export FOO='a'"),
        line.indexOf("export BAR='b'"),
        line.indexOf(r"printf '__YS_%s__\n' DONE"),
        line.indexOf('working dir not found'),
      ];
      for (var i = 0; i < idx.length; i++) {
        expect(idx[i], greaterThanOrEqualTo(0), reason: 'part $i missing');
        if (i > 0) expect(idx[i], greaterThan(idx[i - 1]), reason: 'order $i');
      }
    });

    test('includeInstaller: false omits the SI installer', () {
      final line = svc.buildPayloadLine(
          includeInstaller: false, workingDir: '/srv/app');
      expect(line, isNot(contains('__yourssh_si')));
      expect(line, contains("cd -- '/srv/app'"));
    });

    test('cd failure flag wires to a post-DONE warning', () {
      final line = svc.buildPayloadLine(workingDir: '/nope');
      expect(line, contains('|| __ys_td=1'));
      expect(line, contains(r'[ -n "$__ys_td" ]'));
      expect(line, contains('unset __ys_td'));
      // Warning strictly after DONE so it survives the gate discard.
      expect(line.indexOf('working dir not found'),
          greaterThan(line.indexOf(r"printf '__YS_%s__\n' DONE")));
    });

    test('no cd flag machinery without a workingDir', () {
      expect(svc.buildPayloadLine(envVars: {'A': '1'}),
          isNot(contains('__ys_td')));
    });

    test('skips invalid env keys (defense in depth)', () {
      final line = svc.buildPayloadLine(envVars: {'BAD-KEY': 'x', 'OK': 'y'});
      expect(line, isNot(contains('BAD-KEY')));
      expect(line, contains("export OK='y'"));
    });

    test('quotes dir and values', () {
      final line = svc.buildPayloadLine(
          workingDir: "/data/o'brien", envVars: {'MSG': "it's"});
      expect(line, contains(r"cd -- '/data/o'\''brien'"));
      expect(line, contains(r"export MSG='it'\''s'"));
    });

    test('payload is a single line ending in newline', () {
      final line = svc.buildPayloadLine(
          workingDir: '/srv', envVars: {'A': '1', 'B': '2'});
      expect(line.endsWith('\n'), isTrue);
      expect(line.indexOf('\n'), line.length - 1);
    });

    test('blank workingDir is treated as unset', () {
      expect(svc.buildPayloadLine(workingDir: '  '), svc.buildPayloadLine());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/session_template_payload_test.dart`
Expected: FAIL — `shQuote` / `isValidEnvKey` not defined; named params unknown.

- [ ] **Step 3: Implement in ShellIntegrationService**

In `app/lib/services/shell_integration_service.dart`, add above `buildPayloadLine`:

```dart
  /// Quote [s] for a POSIX single-quoted context (`'` → `'\''`). Control
  /// characters are stripped first: the payload must stay a single line
  /// (`read -rs` consumes exactly one) and no legitimate working dir or
  /// env value needs them.
  static String shQuote(String s) {
    final clean = s.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    return "'${clean.replaceAll("'", "'\\''")}'";
  }

  static final _envKeyRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// POSIX env-var name check. The host panel validates on edit; the
  /// payload builder re-checks as defense in depth (sync can deliver
  /// hosts edited elsewhere).
  static bool isValidEnvKey(String key) => _envKeyRe.hasMatch(key);
```

Replace `buildPayloadLine` (keep its doc comment, extend it):

```dart
  /// Second-phase line: optional hook installer, optional session-template
  /// setup (cd + exports), then the DONE sentinel. Sent only after RDY is
  /// seen, while `read -rs` is consuming stdin — never echoed. DONE carries
  /// a trailing newline so both the remote shell and the app land on a
  /// fresh line (col 0) once the client discards everything up to and
  /// including the sentinel. A failing `cd` raises a flag whose warning
  /// prints *after* DONE — everything before the sentinel is discarded by
  /// the gate, the tail is shown.
  String buildPayloadLine({
    bool includeInstaller = true,
    String? workingDir,
    Map<String, String> envVars = const {},
  }) {
    final dir =
        (workingDir != null && workingDir.trim().isNotEmpty) ? workingDir : null;
    final parts = <String>[];
    if (includeInstaller) {
      final body = buildInjectionScript(); // ends with '\n'
      parts.add(body.substring(0, body.length - 1));
    }
    if (dir != null) {
      parts.add('cd -- ${shQuote(dir)} 2>/dev/null || __ys_td=1');
    }
    for (final e in envVars.entries) {
      if (!isValidEnvKey(e.key)) continue;
      parts.add('export ${e.key}=${shQuote(e.value)}');
    }
    parts.add("printf '__YS_%s__\\n' DONE");
    if (dir != null) {
      parts.add('[ -n "\$__ys_td" ] && '
          "printf 'yourssh: working dir not found: %s\\r\\n' ${shQuote(dir)}; "
          'unset __ys_td');
    }
    return '${parts.join('; ')}\n';
  }
```

In `app/lib/providers/shell_integration_provider.dart` replace the delegation (line 20):

```dart
  String buildPayloadLine({
    bool includeInstaller = true,
    String? workingDir,
    Map<String, String> envVars = const {},
  }) =>
      _service.buildPayloadLine(
        includeInstaller: includeInstaller,
        workingDir: workingDir,
        envVars: envVars,
      );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/session_template_payload_test.dart test/services/shell_integration_service_test.dart test/providers/shell_integration_provider_test.dart`
Expected: PASS — new tests green, legacy payload tests untouched (defaults are byte-identical).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/shell_integration_service.dart app/lib/providers/shell_integration_provider.dart app/test/services/session_template_payload_test.dart
git commit -m "feat: session-template payload in invisible-injection builder"
```

---

### Task 3: openShell — template-driven handshake + payload args

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (openShell, ~lines 433–650)
- Test: `app/test/services/ssh_service_open_shell_test.dart` (extend)

- [ ] **Step 1: Extend the fake shell to capture writes and emit stdout**

In `app/test/services/ssh_service_open_shell_test.dart`, add `import 'dart:convert';` to the imports, then replace `_FakeShell.write` (currently a no-op) and add helpers:

```dart
  final writes = <String>[];
  String get writtenText => writes.join();

  @override
  void write(Uint8List data) {
    writes.add(const Utf8Decoder().convert(data));
  }

  void emitStdout(String text) =>
      _stdout.add(Uint8List.fromList(const Utf8Encoder().convert(text)));
```

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: PASS (existing tests unaffected — they never inspected writes).

- [ ] **Step 2: Write the failing tests**

Add to the same file (inside `main()`), plus imports `import 'package:yourssh/providers/shell_integration_provider.dart';`:

```dart
  // > 250 ms bracketed-paste settle timer inside openShell.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  group('session template injection', () {
    test('template-only host (SI off) injects cd/export without installer',
        () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          workingDir: '/srv/app',
          envVars: {'FOO': 'bar baz'});
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();

      shell.emitStdout('\x1b[?2004h\$ '); // line editor reading
      await settle();
      expect(shell.writtenText, contains('IFS= read -rs __ys'),
          reason: 'bootstrap must be written after readiness');

      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();
      expect(shell.writtenText, contains("cd -- '/srv/app' 2>/dev/null"));
      expect(shell.writtenText, contains("export FOO='bar baz'"));
      expect(shell.writtenText, isNot(contains('__yourssh_si')),
          reason: 'SI off → no installer in the payload');

      shell.emitStdout('echo-head __YS_DONE__\n');
      await pumpEventQueue();

      await shell.close();
      await shellDone;
    });

    test('SI on + template → payload has installer AND cd', () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          workingDir: '/srv/app');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();

      expect(shell.writtenText, contains('__yourssh_si'));
      expect(shell.writtenText, contains("cd -- '/srv/app'"));

      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();
      await shell.close();
      await shellDone;
    });

    test('no ShellIntegrationProvider wired → template host stays silent',
        () async {
      final svc = SshService(StorageService()); // no provider
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          workingDir: '/srv/app');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();

      expect(shell.writes, isEmpty);

      await shell.close();
      await shellDone;
    });
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: first two new tests FAIL (no bootstrap written — handshake only launches when `siOn`, and `buildPayloadLine` is called with no args). Third passes by construction.

- [ ] **Step 4: Implement the gating in openShell**

In `app/lib/services/ssh_service.dart`:

After the `siOn` declaration block (ends line ~443), add:

```dart
    // Session-template setup (cd/export, and the snippet's DONE trigger)
    // rides the same invisible handshake as shell integration — one
    // bootstrap, one payload, one DONE sentinel. See
    // docs/superpowers/specs/2026-06-06-session-template-design.md.
    final injectOn =
        shellIntegration != null && (siOn || session.host.hasTemplateSetup);
```

Then swap the handshake guards from `siOn` to `injectOn` in exactly these five places (leave the `session.terminal.onPrivateOSC` wiring and the agent-forwarding/OSC code on `siOn`):

1. `launchInjection()`: `if (!siOn || gate != null || injectionAborted) return;` → `if (!injectOn || gate != null || injectionAborted) return;`
2. `armQuietProbe()`: `if (!siOn ||` → `if (!injectOn ||`
3. `if (siOn) armQuietProbe();` → `if (injectOn) armQuietProbe();`
4. stdout listener readiness block: `if (siOn && gate == null && !injectionAborted) {` → `if (injectOn && gate == null && !injectionAborted) {`
5. `onOutput` user-keystroke abort: `if (siOn && gate == null && !injectionAborted) {` → `if (injectOn && gate == null && !injectionAborted) {`

Replace the payload write (line ~594):

```dart
          if (r.sendPayload) {
            shell.write(Uint8List.fromList(const Utf8Encoder().convert(
                shellIntegration!.buildPayloadLine(
              includeInstaller: siOn,
              workingDir: session.host.workingDir,
              envVars: session.host.envVars,
            ))));
          }
```

(`Utf8Encoder` because workingDir/env values may be non-ASCII; the local `const utf8 = Utf8Decoder(...)` shadows `dart:convert`'s `utf8`, so use the encoder class directly. `dart:convert` is already imported.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart test/services/injection_gate_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_open_shell_test.dart
git commit -m "feat: session-template cd/export ride the invisible handshake"
```

---

### Task 4: openShell — startup snippet rules

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (openShell)
- Test: `app/test/services/ssh_service_open_shell_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Add to the `session template injection` group (uses the `settle()` helper and fake from Task 3):

```dart
    test('startup snippet typed exactly once after DONE', () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();
      expect(shell.writes, isNot(contains('htop\n')),
          reason: 'snippet must wait for DONE');

      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();
      expect(shell.writes.where((w) => w == 'htop\n').length, 1);

      shell.emitStdout('regular output after handshake');
      await pumpEventQueue();
      expect(shell.writes.where((w) => w == 'htop\n').length, 1,
          reason: 'never re-sent');

      await shell.close();
      await shellDone;
    });

    test('non-bash fallback (DONE without RDY) still types the snippet',
        () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      final writesAfterBootstrap = shell.writes.length;

      // fish/other POSIX shells: bootstrap's `|| printf DONE` branch.
      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();

      expect(shell.writes.where((w) => w == 'htop\n').length, 1);
      // No RDY → payload was never sent: bootstrap + snippet only.
      expect(shell.writes.length, writesAfterBootstrap + 1);

      await shell.close();
      await shellDone;
    });

    test('tmux on → hidden setup runs, snippet skipped', () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          workingDir: '/srv/app',
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session, useTmux: true);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();
      expect(shell.writtenText, contains("cd -- '/srv/app'"));

      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();
      expect(shell.writes, isNot(contains('htop\n')),
          reason: 'a tmux re-attach would replay the snippet — skip it');

      await shell.close();
      await shellDone;
    });

    test('user keystroke before handshake aborts setup AND snippet',
        () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();

      session.terminal.onOutput?.call('x'); // user typed first
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();

      expect(shell.writes, ['x'],
          reason: 'no bootstrap, no snippet — the user owns the session');

      await shell.close();
      await shellDone;
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: the three snippet tests FAIL (`htop\n` never written); the abort test passes already (gating from Task 3) — keep it as a regression pin.

- [ ] **Step 3: Implement the snippet send**

In `openShell`, after the `injectOn` declaration from Task 3, add:

```dart
    var snippetSent = false;
    void maybeSendStartupSnippet() {
      if (snippetSent) return;
      snippetSent = true;
      final snippet = session.host.startupSnippet;
      // tmux `new -A` re-attach would replay the snippet into a live
      // session — cd/export are idempotent, the snippet is not. Skip it.
      if (snippet == null || snippet.trim().isEmpty || useTmux) return;
      shell.write(Uint8List.fromList(const Utf8Encoder()
          .convert(snippet.endsWith('\n') ? snippet : '$snippet\n')));
    }
```

In the stdout listener, extend the gate-completion branch (currently `if (wasHolding && !g.isHolding) doneTimer?.cancel();`):

```dart
          if (wasHolding && !g.isHolding) {
            doneTimer?.cancel();
            // DONE seen: handshake completed cleanly — type the startup
            // snippet exactly as if the user had, visible and recorded.
            // The doneTimer flush path (degraded handshake) never lands
            // here, so an unconfirmed handshake never types the snippet.
            maybeSendStartupSnippet();
          }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: PASS, all tests in the file.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_open_shell_test.dart
git commit -m "feat: visible startup snippet typed after handshake DONE"
```

---

### Task 5: SessionProvider — per-host TERM/tmux resolution

**Files:**
- Modify: `app/lib/providers/session_provider.dart:157-161`
- Test: `app/test/providers/session_provider_template_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `app/test/providers/session_provider_template_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key_entry.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _NullClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Captures what _doConnect resolves; never touches the network.
class _CapturingSsh extends SshService {
  _CapturingSsh() : super(StorageService());

  bool? capturedUseTmux;
  String? capturedTermType;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async =>
      _NullClient();

  @override
  Future<void> openShell(
    SshSession session, {
    bool useTmux = false,
    String termType = 'xterm-256color',
  }) async {
    capturedUseTmux = useTmux;
    capturedTermType = termType;
  }
}

// detectedOs set so _doConnect skips the detectOs probe (would hit the
// _NullClient and throw).
Host _host({String? termType, bool? tmuxOverride}) => Host(
      label: 'h',
      host: 'h.com',
      username: 'u',
      detectedOs: 'ubuntu',
      termType: termType,
      tmuxOverride: tmuxOverride,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('per-host TERM/tmux overrides beat the global callbacks', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    p.tmuxEnabled = () => false;
    p.terminalType = () => 'xterm-256color';

    await p.connect(_host(termType: 'vt100', tmuxOverride: true));

    expect(ssh.capturedTermType, 'vt100');
    expect(ssh.capturedUseTmux, isTrue);
    p.dispose();
  });

  test('null overrides follow the globals', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    p.tmuxEnabled = () => true;
    p.terminalType = () => 'linux';

    await p.connect(_host());

    expect(ssh.capturedTermType, 'linux');
    expect(ssh.capturedUseTmux, isTrue);
    p.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/session_provider_template_test.dart`
Expected: first test FAILS (`capturedTermType` is `xterm-256color`, not `vt100`); second passes.

- [ ] **Step 3: Implement the resolution**

In `app/lib/providers/session_provider.dart` (`_doConnect`, lines 157–161):

```dart
      await _ssh.openShell(
        session,
        useTmux: host.tmuxOverride ?? tmuxEnabled?.call() ?? false,
        termType: host.termType ?? terminalType?.call() ?? 'xterm-256color',
      );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/session_provider_template_test.dart test/providers/session_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_template_test.dart
git commit -m "feat: per-host TERM and tmux overrides"
```

---

### Task 6: Appearance resolver util

**Files:**
- Create: `app/lib/util/terminal_appearance.dart`
- Test: `app/test/util/terminal_appearance_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `app/test/util/terminal_appearance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/terminal_appearance.dart';

void main() {
  TerminalAppearance resolve(Host? host) => resolveTerminalAppearance(
        host: host,
        globalTheme: 'Dracula',
        globalFont: 'MesloLGS NF',
        globalFontSize: 13,
      );

  test('null host → globals', () {
    final a = resolve(null);
    expect(a.themeName, 'Dracula');
    expect(a.fontFamily, 'MesloLGS NF');
    expect(a.fontSize, 13);
  });

  test('host without overrides → globals', () {
    final a = resolve(Host(label: 'h', host: 'h.com', username: 'u'));
    expect(a.themeName, 'Dracula');
    expect(a.fontFamily, 'MesloLGS NF');
    expect(a.fontSize, 13);
  });

  test('host overrides win', () {
    final a = resolve(Host(
        label: 'h',
        host: 'h.com',
        username: 'u',
        terminalThemeId: 'Nord',
        fontFamily: 'monospace',
        fontSize: 16));
    expect(a.themeName, 'Nord');
    expect(a.fontFamily, 'monospace');
    expect(a.fontSize, 16);
  });

  test('unknown host theme falls back to the GLOBAL theme, not catalog[0]',
      () {
    final a = resolve(Host(
        label: 'h', host: 'h.com', username: 'u', terminalThemeId: 'Nope'));
    expect(a.themeName, 'Dracula');
  });
}
```

(If `'Nord'` is not an exact name in `kTerminalThemeNames` — check `app/lib/theme/terminal_themes.dart` — substitute any exact catalog name, e.g. `'Nord Light'`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/util/terminal_appearance_test.dart`
Expected: FAIL — file/function don't exist.

- [ ] **Step 3: Implement the resolver**

Create `app/lib/util/terminal_appearance.dart`:

```dart
import '../models/host.dart';
import '../theme/terminal_themes.dart';

/// Resolved terminal look for one session: per-host overrides falling back
/// to the global Settings → Terminal values.
class TerminalAppearance {
  final String themeName;
  final String fontFamily;
  final double fontSize;
  const TerminalAppearance({
    required this.themeName,
    required this.fontFamily,
    required this.fontSize,
  });
}

/// Per-host appearance overrides beat the globals; null host or null field
/// = global. An unknown per-host theme name (catalog drift across versions
/// via sync) falls back to the global theme rather than catalog[0].
TerminalAppearance resolveTerminalAppearance({
  required Host? host,
  required String globalTheme,
  required String globalFont,
  required double globalFontSize,
}) {
  final hostTheme = host?.terminalThemeId;
  final themeKnown =
      hostTheme != null && kTerminalThemeNames.contains(hostTheme);
  return TerminalAppearance(
    themeName: themeKnown ? hostTheme : globalTheme,
    fontFamily: host?.fontFamily ?? globalFont,
    fontSize: host?.fontSize ?? globalFontSize,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/util/terminal_appearance_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/terminal_appearance.dart app/test/util/terminal_appearance_test.dart
git commit -m "feat: per-host terminal appearance resolver"
```

---

### Task 7: terminal_view — apply per-host appearance

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart` (lines ~145, ~176, ~222, ~252, ~398–434)

No new test file: the resolver is unit-tested (Task 6) and this task is mechanical wiring; the full suite + `flutter analyze` guard regressions. Existing terminal_view tests (if any pump without `HostProvider`) are protected by the fallback below.

- [ ] **Step 1: Add the appearance helper**

Imports to add at the top of `app/lib/widgets/terminal_view.dart`:

```dart
import 'package:provider/provider.dart';            // already imported — skip if present
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../util/terminal_appearance.dart';
```

Add to `_TerminalWidgetState`:

```dart
  /// Per-host appearance resolved against globals. The fresh host is looked
  /// up by id — the session's Host snapshot goes stale after copyWith (same
  /// pattern as SessionTab). HostProvider can be absent in widget tests →
  /// fall back to the snapshot.
  TerminalAppearance _appearance({required bool watch}) {
    final settings = watch
        ? context.watch<SettingsProvider>()
        : context.read<SettingsProvider>();
    Host? fresh;
    try {
      final hosts =
          watch ? context.watch<HostProvider>() : context.read<HostProvider>();
      for (final h in hosts.allHosts) {
        if (h.id == widget.session.host.id) {
          fresh = h;
          break;
        }
      }
    } on ProviderNotFoundException {
      // Tests pump this widget without a HostProvider.
    }
    return resolveTerminalAppearance(
      host: fresh ?? widget.session.host,
      globalTheme: settings.terminalTheme,
      globalFont: settings.terminalFont,
      globalFontSize: settings.fontSize,
    );
  }
```

- [ ] **Step 2: Replace the raw settings reads**

Five sites:

1. Line ~144–145 (search highlight):
```dart
    final termTheme = terminalThemeByName(_appearance(watch: false).themeName);
```
(drop the now-unused `final settings = context.read<SettingsProvider>();` line if nothing else in that method uses it)

2. Line ~176:
```dart
  double get _lineHeightPx => _appearance(watch: false).fontSize * 1.2;
```

3. Lines ~222–223 and ~252–253 (two more `terminalThemeByName(context.read<SettingsProvider>().terminalTheme)` sites):
```dart
    final termTheme = terminalThemeByName(_appearance(watch: false).themeName);
```

4. `build()` (lines ~398–414):
```dart
    final settings = context.watch<SettingsProvider>();
    final appearance = _appearance(watch: true);
    final theme = terminalThemeByName(appearance.themeName);
    final showGutter = settings.shellIntegrationEnabled &&
        widget.session.host.shellIntegration;
    ...
          textStyle: TerminalStyle(
            fontSize: appearance.fontSize,
            fontFamily: appearance.fontFamily,
          ),
```

5. Gutter `lineHeight` (line ~434):
```dart
              lineHeight: appearance.fontSize * 1.2,
```

- [ ] **Step 3: Analyze and run the suite**

Run: `cd app && flutter analyze && flutter test`
Expected: 0 analyzer issues; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: per-host theme/font overrides in the terminal view"
```

---

### Task 8: HostDetailPanel — SESSION TEMPLATE section

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart`
- Test: `app/test/widgets/host_detail_panel_template_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

Create `app/test/widgets/host_detail_panel_template_test.dart` (pump harness mirrors `host_detail_panel_agent_forwarding_test.dart`; save button is `find.text('SAVE ONLY')`):

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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 3600));
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

  Future<void> save(WidgetTester tester) async {
    final btn = find.text('SAVE ONLY');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  Host existingHost() => Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'root',
        workingDir: '/srv/app',
        envVars: {'FOO': 'bar'},
        startupSnippet: 'htop',
        terminalThemeId: 'Dracula',
        termType: 'vt100',
        tmuxOverride: true,
      );

  testWidgets('populates template fields from the existing host',
      (tester) async {
    await pumpPanel(tester, existing: existingHost());
    expect(find.text('/srv/app'), findsOneWidget);
    expect(find.text('FOO'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
    expect(find.text('htop'), findsOneWidget);
  });

  testWidgets('round-trips template fields through save', (tester) async {
    await pumpPanel(tester, existing: existingHost());
    await save(tester);
    expect(saved, isNotNull);
    expect(saved!.workingDir, '/srv/app');
    expect(saved!.envVars, {'FOO': 'bar'});
    expect(saved!.startupSnippet, 'htop');
    expect(saved!.terminalThemeId, 'Dracula');
    expect(saved!.termType, 'vt100');
    expect(saved!.tmuxOverride, isTrue);
  });

  testWidgets('empty template fields save as null/empty', (tester) async {
    await pumpPanel(tester,
        existing: Host(label: 'srv', host: '1.2.3.4', username: 'root'));
    await save(tester);
    expect(saved, isNotNull);
    expect(saved!.workingDir, isNull);
    expect(saved!.envVars, isEmpty);
    expect(saved!.startupSnippet, isNull);
    expect(saved!.hasTemplateSetup, isFalse);
  });

  testWidgets('invalid env var name blocks save', (tester) async {
    await pumpPanel(tester, existing: existingHost());
    await tester.enterText(find.widgetWithText(TextFormField, 'FOO'), 'BAD-NAME');
    await save(tester);
    expect(saved, isNull, reason: 'form validation must block the save');
  });

  testWidgets('env rows can be added via the add button', (tester) async {
    await pumpPanel(tester,
        existing: Host(label: 'srv', host: '1.2.3.4', username: 'root'));
    final add = find.text('Add env variable');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'NAME'), 'PATH_X');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'value'), '/opt/x');
    await save(tester);
    expect(saved!.envVars, {'PATH_X': '/opt/x'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/host_detail_panel_template_test.dart`
Expected: FAIL — no template fields rendered, saved host lacks fields.

- [ ] **Step 3: Implement panel state**

In `app/lib/widgets/host_detail_panel.dart`:

Imports to add:

```dart
import '../services/shell_integration_service.dart';
import '../theme/terminal_themes.dart';
import 'terminal_appearance_controls.dart' show kBundledTerminalFonts;
```

File-level const (near the top, after imports):

```dart
/// Mirrors the TERM presets in Settings → Terminal.
const _kTermTypes = ['xterm-256color', 'xterm', 'linux', 'vt100'];
```

State fields (after `bool _agentForwarding = false;`):

```dart
  late final TextEditingController _workingDirCtrl;
  late final TextEditingController _startupSnippetCtrl;
  late final TextEditingController _fontSizeCtrl;
  final List<({TextEditingController key, TextEditingController value})>
      _envRows = [];
  String? _templateTheme;
  String? _templateFont;
  String? _templateTermType;
  bool? _tmuxOverride;
```

`initState` additions (after `_agentForwarding = h?.agentForwarding ?? false;`):

```dart
    _workingDirCtrl = TextEditingController(text: h?.workingDir ?? '');
    _startupSnippetCtrl = TextEditingController(text: h?.startupSnippet ?? '');
    _fontSizeCtrl = TextEditingController(text: _fmtFontSize(h?.fontSize));
    for (final e in (h?.envVars ?? const <String, String>{}).entries) {
      _envRows.add((
        key: TextEditingController(text: e.key),
        value: TextEditingController(text: e.value),
      ));
    }
    _templateTheme = h?.terminalThemeId;
    _templateFont = h?.fontFamily;
    _templateTermType = h?.termType;
    _tmuxOverride = h?.tmuxOverride;
```

Helper (static method on the state class):

```dart
  static String _fmtFontSize(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
```

`dispose` — extend the controller loop:

```dart
    for (final c in [
      _hostCtrl, _labelCtrl, _groupCtrl, _tagsCtrl, _portCtrl, _usernameCtrl,
      _passwordCtrl, _sftpCommand, _workingDirCtrl, _startupSnippetCtrl,
      _fontSizeCtrl,
    ]) {
      c.dispose();
    }
    for (final r in _envRows) {
      r.key.dispose();
      r.value.dispose();
    }
```

`_save` — add to the `Host(...)` construction (after `sftpServerCommand:`):

```dart
      workingDir: _workingDirCtrl.text.trim().isEmpty
          ? null
          : _workingDirCtrl.text.trim(),
      envVars: {
        for (final r in _envRows)
          if (r.key.text.trim().isNotEmpty) r.key.text.trim(): r.value.text,
      },
      startupSnippet: _startupSnippetCtrl.text.trim().isEmpty
          ? null
          : _startupSnippetCtrl.text,
      terminalThemeId: _templateTheme,
      fontFamily: _templateFont,
      fontSize: double.tryParse(_fontSizeCtrl.text.trim()),
      termType: _templateTermType,
      tmuxOverride: _tmuxOverride,
```

- [ ] **Step 4: Implement the SESSION TEMPLATE card**

Insert after the SESSION `_Card`'s closing `]),` (after the `AgentStatusLine` block, before `const SizedBox(height: 24),`):

```dart
                  const SizedBox(height: 16),
                  _sectionLabel('SESSION TEMPLATE'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    _PanelField(
                        controller: _workingDirCtrl,
                        hint: 'Working directory (bash/zsh only)',
                        icon: Icons.folder_open),
                    _divider(),
                    for (var i = 0; i < _envRows.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Row(children: [
                          const Icon(Icons.data_object,
                              size: 16, color: AppColors.textTertiary),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _envRows[i].key,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'NAME',
                                hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              validator: (v) => (v == null ||
                                      v.trim().isEmpty ||
                                      ShellIntegrationService.isValidEnvKey(
                                          v.trim()))
                                  ? null
                                  : 'A–Z, 0–9, _ only',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _envRows[i].value,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'value',
                                hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close,
                                size: 14, color: AppColors.textTertiary),
                            onPressed: () => setState(() {
                              final row = _envRows.removeAt(i);
                              // Dispose after the frame: the row's fields
                              // are still mounted during this build.
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                row.key.dispose();
                                row.value.dispose();
                              });
                            }),
                          ),
                        ]),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _envRows.add((
                              key: TextEditingController(),
                              value: TextEditingController(),
                            ))),
                        icon: const Icon(Icons.add,
                            size: 14, color: AppColors.accent),
                        label: const Text('Add env variable',
                            style: TextStyle(
                                color: AppColors.accent, fontSize: 12)),
                      ),
                    ),
                    _divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.play_arrow_outlined,
                                size: 16, color: AppColors.textTertiary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _startupSnippetCtrl,
                              minLines: 2,
                              maxLines: 4,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                hintText:
                                    'Startup snippet — typed into the shell '
                                    'after connect. Skipped when tmux is on.',
                                hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _divider(),
                    _DropdownRow(
                      icon: Icons.palette_outlined,
                      child: DropdownButton<String?>(
                        value: _templateTheme,
                        isExpanded: true,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                        dropdownColor: AppColors.card,
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Theme: follow global')),
                          for (final name in kTerminalThemeNames)
                            DropdownMenuItem<String?>(
                                value: name, child: Text(name)),
                        ],
                        onChanged: (v) => setState(() => _templateTheme = v),
                      ),
                    ),
                    _divider(),
                    _DropdownRow(
                      icon: Icons.text_fields,
                      child: Row(children: [
                        Expanded(
                          child: DropdownButton<String?>(
                            value: _templateFont,
                            isExpanded: true,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                            dropdownColor: AppColors.card,
                            underline: const SizedBox(),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Font: follow global')),
                              for (final f in kBundledTerminalFonts)
                                DropdownMenuItem<String?>(
                                    value: f, child: Text(f)),
                            ],
                            onChanged: (v) =>
                                setState(() => _templateFont = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 56,
                          child: TextFormField(
                            controller: _fontSizeCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'size',
                              hintStyle: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return null;
                              final d = double.tryParse(t);
                              return (d == null || d < 6 || d > 40)
                                  ? '6–40'
                                  : null;
                            },
                          ),
                        ),
                      ]),
                    ),
                    _divider(),
                    _DropdownRow(
                      icon: Icons.terminal_outlined,
                      child: DropdownButton<String?>(
                        value: _templateTermType,
                        isExpanded: true,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                        dropdownColor: AppColors.card,
                        underline: const SizedBox(),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('TERM: follow global')),
                          for (final t in _kTermTypes)
                            DropdownMenuItem<String?>(
                                value: t, child: Text(t)),
                        ],
                        onChanged: (v) =>
                            setState(() => _templateTermType = v),
                      ),
                    ),
                    _divider(),
                    _DropdownRow(
                      icon: Icons.grid_view_outlined,
                      child: DropdownButton<bool?>(
                        value: _tmuxOverride,
                        isExpanded: true,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                        dropdownColor: AppColors.card,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem<bool?>(
                              value: null, child: Text('tmux: follow global')),
                          DropdownMenuItem<bool?>(
                              value: true, child: Text('tmux: always on')),
                          DropdownMenuItem<bool?>(
                              value: false, child: Text('tmux: always off')),
                        ],
                        onChanged: (v) => setState(() => _tmuxOverride = v),
                      ),
                    ),
                  ]),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/host_detail_panel_template_test.dart test/widgets/host_detail_panel_agent_forwarding_test.dart test/widgets/host_detail_panel_chain_test.dart`
Expected: PASS — new tests green, existing panel tests unaffected. If the existing panel tests fail on surface height (taller panel), bump their `setSurfaceSize` height the same way.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart app/test/widgets/host_detail_panel_template_test.dart
git commit -m "feat: SESSION TEMPLATE section in the host panel"
```

---

### Task 9: Full verification + docs

**Files:**
- Modify: `CLAUDE.md` (Key models + Services bullets)

- [ ] **Step 1: Full analyze + test run**

Run: `cd app && flutter analyze && flutter test`
Expected: 0 issues, all tests pass. Fix anything that surfaces before proceeding.

- [ ] **Step 2: Update CLAUDE.md**

In the **Key models** section, extend the `Host` bullet:

```markdown
- `Host` — connection profile (host, port, username, `AuthType`: `password` / `privateKey` / `certificate` / `agent`; `agentForwarding` opt-in per host, default off; session template fields — `workingDir` + `envVars` delivered invisibly via the shell-integration handshake, `startupSnippet` typed visibly after DONE (skipped under tmux), `terminalThemeId`/`fontFamily`/`fontSize`/`termType`/`tmuxOverride` nullable per-host overrides falling back to globals; `hasTemplateSetup` drives the handshake when shell integration is off)
```

In the **Services** section, extend the `ShellIntegrationService` bullet — after the `buildPayloadLine()` mention, note:

```markdown
`buildPayloadLine({includeInstaller, workingDir, envVars})` also carries the session-template setup (`cd -- '<dir>'` + `export K='v'`, single-quote-escaped via `shQuote`, keys checked by `isValidEnvKey`); a failing cd prints a warning placed *after* the DONE sentinel so it survives the gate discard
```

And in **Utils**, add:

```markdown
- `terminal_appearance.dart` — `resolveTerminalAppearance` merges per-host theme/font/size overrides with the global Settings → Terminal values (unknown theme name → global, not catalog[0]); consumed by `terminal_view.dart` with a fresh-host lookup
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: session template in CLAUDE.md"
```

---

## Self-review notes (already applied)

- **Spec coverage:** model fields (T1), hidden cd/export via handshake incl. non-bash skip + cd-failure warning (T2/T3), visible snippet + tmux/abort/non-bash rules (T4), TERM/tmux resolution (T5), theme/font resolution + live updates (T6/T7), panel UI + validation (T8), sync tolerance (T1 fromJson tests; `buildPayload` strips only `detectedOs` — no change needed), docs (T9).
- **Type consistency:** `hasTemplateSetup` (T1) used in T3; `shQuote`/`isValidEnvKey` static on `ShellIntegrationService` (T2) used in T8's validator; `TerminalAppearance.themeName/fontFamily/fontSize` (T6) used in T7.
- Snippet-only host works because `hasTemplateSetup` includes `startupSnippet` (T1) — DONE (or its non-bash fallback) is the send trigger (T4 tests both).
- Deviation from spec example: one `export` per variable instead of one combined `export K1=… K2=…` — functionally identical, simpler to build/test.
