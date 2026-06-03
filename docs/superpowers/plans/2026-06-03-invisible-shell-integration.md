# Invisible Shell Integration Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the OSC 7/133 shell-integration injection completely invisible on connect — the script is never painted in the terminal.

**Architecture:** Two-phase handshake: a ~100-char bootstrap line prints a `__YS_RDY__` sentinel and blocks in `read -rs`; the real hook-installer payload is sent only after RDY and is therefore never echoed. A pure `InjectionGate` withholds output between bootstrap send and the `__YS_DONE__` sentinel; `SshService` then writes the held text plus an erase sequence in the same frame, so the bootstrap echo is wiped before it is ever painted. Spec: `docs/superpowers/specs/2026-06-03-invisible-shell-integration-design.md`.

**Tech Stack:** Dart/Flutter, xterm.dart `Terminal`, dartssh2 shell channel, `flutter_test`.

---

## File structure

- Modify `app/lib/services/shell_integration_service.dart` — sentinel constants, `buildBootstrapLine()`, `buildPayloadLine()`, `buildEraseSequence(rows)`. `buildInjectionScript()` stays as the shared hook-installer body.
- Create `app/lib/services/injection_gate.dart` — pure withhold/scan state machine (`GateResult`, `InjectionGate`).
- Modify `app/lib/services/ssh_service.dart` (`openShell`, lines ~377–428) — quiescence timer, gate wiring, payload send, erase write, timeout/close cleanup.
- Modify `app/test/services/shell_integration_service_test.dart` — tests for the new builders.
- Create `app/test/services/injection_gate_test.dart` — gate state-machine tests.
- Modify `CHANGELOG.md` — `[Unreleased]` entry.

All commands run from `app/` unless noted. The repo hook may rewrite commands through `rtk` — that is expected and transparent.

---

### Task 1: Protocol builders in `ShellIntegrationService`

**Files:**
- Modify: `app/lib/services/shell_integration_service.dart`
- Test: `app/test/services/shell_integration_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to the end of `main()` in `app/test/services/shell_integration_service_test.dart`:

```dart
  group('buildBootstrapLine', () {
    final boot = s.buildBootstrapLine();
    test('is one short line guarded on bash/zsh', () {
      expect('\n'.allMatches(boot).length, 1); // trailing newline only
      expect(boot.endsWith('\n'), isTrue);
      expect(boot, contains(r'$BASH_VERSION$ZSH_VERSION'));
      expect(boot.length, lessThan(160)); // must stay short: its echo can wrap
    });
    test('reads payload silently and evals it', () {
      expect(boot, contains('IFS= read -rs __ys'));
      expect(boot, contains(r'eval "$__ys"'));
      expect(boot, contains('unset __ys'));
    });
    test('sentinel literals never appear in the bootstrap source (echo-safe)', () {
      // printf '__YS_%s__' RDY builds the sentinel at runtime, so scanning the
      // output stream can never false-positive on the echoed command line.
      expect(boot, isNot(contains(ShellIntegrationService.kReadySentinel)));
      expect(boot, isNot(contains(ShellIntegrationService.kDoneSentinel)));
      expect(boot, contains("printf '__YS_%s__' RDY"));
      expect(boot, contains("printf '__YS_%s__' DONE")); // non-bash/zsh branch
    });
  });

  group('buildPayloadLine', () {
    final payload = s.buildPayloadLine();
    test('is the hook installer terminated by the DONE printf', () {
      expect('\n'.allMatches(payload).length, 1);
      expect(payload.endsWith("printf '__YS_%s__' DONE\n"), isTrue);
      // Hook-installer body is unchanged.
      final body = s.buildInjectionScript();
      expect(payload, startsWith(body.substring(0, body.length - 1)));
    });
    test('sentinel literal never appears in the payload source', () {
      expect(payload, isNot(contains(ShellIntegrationService.kDoneSentinel)));
    });
  });

  group('buildEraseSequence', () {
    test('zero rows: return to col 0 and clear below', () {
      expect(ShellIntegrationService.buildEraseSequence(0), '\r\x1b[0J');
    });
    test('n rows: cursor up n then clear below', () {
      expect(ShellIntegrationService.buildEraseSequence(3), '\r\x1b[3A\x1b[0J');
    });
    test('negative clamps to zero', () {
      expect(ShellIntegrationService.buildEraseSequence(-2), '\r\x1b[0J');
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/shell_integration_service_test.dart`
Expected: COMPILE ERROR — `kReadySentinel`, `buildBootstrapLine` etc. not defined.

- [ ] **Step 3: Implement the builders**

In `app/lib/services/shell_integration_service.dart`, inside `ShellIntegrationService`, add above `buildInjectionScript()`:

```dart
  /// Sentinels printed by the injected shell code. Built at runtime with
  /// `printf '__YS_%s__' RDY` so the literal string never appears in the
  /// echoed command line — the output scanner cannot false-positive on echo.
  static const kReadySentinel = '__YS_RDY__';
  static const kDoneSentinel = '__YS_DONE__';

  /// Short first-phase line written to the shell instead of the full script.
  /// bash/zsh: prints RDY, then blocks in `read -rs` so the payload that
  /// follows is consumed raw and never echoed. Other POSIX shells: prints
  /// DONE immediately so the client skips the payload and cleans up.
  String buildBootstrapLine() =>
      r'[ -n "$BASH_VERSION$ZSH_VERSION" ] && '
      r"{ printf '__YS_%s__' RDY; IFS= read -rs __ys; "
      r'eval "$__ys"; unset __ys; } '
      r"|| printf '__YS_%s__' DONE"
      '\n';

  /// Second-phase line: the hook installer plus the DONE sentinel. Sent only
  /// after RDY is seen, while `read -rs` is consuming stdin — never echoed.
  String buildPayloadLine() {
    final body = buildInjectionScript(); // ends with '\n'
    return '${body.substring(0, body.length - 1)}; '
        "printf '__YS_%s__' DONE\n";
  }

  /// ANSI sequence erasing the bootstrap echo region: col 0, up [rows],
  /// clear to end of screen. Written by the client in the same frame as the
  /// withheld output, so the echo is never painted.
  static String buildEraseSequence(int rows) =>
      rows > 0 ? '\r\x1b[${rows}A\x1b[0J' : '\r\x1b[0J';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/shell_integration_service_test.dart`
Expected: PASS (all groups, including pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/shell_integration_service.dart app/test/services/shell_integration_service_test.dart
git commit -m "feat(shell-integration): two-phase bootstrap/payload protocol builders"
```

---

### Task 2: `InjectionGate` pure state machine

**Files:**
- Create: `app/lib/services/injection_gate.dart`
- Test: `app/test/services/injection_gate_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/services/injection_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/injection_gate.dart';

void main() {
  InjectionGate gate() =>
      InjectionGate(readySentinel: '__YS_RDY__', doneSentinel: '__YS_DONE__');

  test('withholds output until DONE', () {
    final g = gate();
    expect(g.feed('motd echo').emit, isNull);
    expect(g.isHolding, isTrue);
  });

  test('RDY triggers sendPayload exactly once', () {
    final g = gate();
    expect(g.feed('x__YS_RDY__').sendPayload, isTrue);
    expect(g.feed('more __YS_RDY__ again').sendPayload, isFalse);
  });

  test('RDY split across chunks still triggers', () {
    final g = gate();
    expect(g.feed('echo __YS_R').sendPayload, isFalse);
    expect(g.feed('DY__').sendPayload, isTrue);
  });

  test('DONE releases everything with sentinels stripped', () {
    final g = gate();
    g.feed('A__YS_RDY__B');
    final r = g.feed('C__YS_DONE__D');
    expect(r.emit, 'ABCD');
    expect(g.isHolding, isFalse);
  });

  test('DONE without RDY (non-bash/zsh) flushes without payload', () {
    final g = gate();
    final r = g.feed('echo__YS_DONE__');
    expect(r.emit, 'echo');
    expect(r.sendPayload, isFalse);
  });

  test('RDY and DONE in the same chunk sends payload and flushes', () {
    final g = gate();
    final r = g.feed('__YS_RDY____YS_DONE__tail');
    expect(r.sendPayload, isTrue);
    expect(r.emit, 'tail');
  });

  test('passthrough after DONE', () {
    final g = gate();
    g.feed('__YS_DONE__');
    expect(g.feed('hello').emit, 'hello');
  });

  test('flush releases held text and stops gating', () {
    final g = gate();
    g.feed('partial __YS_R');
    expect(g.flush(), 'partial __YS_R');
    expect(g.isHolding, isFalse);
    expect(g.feed('after').emit, 'after');
  });

  test('heldLength tracks the withheld buffer', () {
    final g = gate();
    g.feed('12345');
    expect(g.heldLength, 5);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/injection_gate_test.dart`
Expected: COMPILE ERROR — `injection_gate.dart` does not exist.

- [ ] **Step 3: Implement the gate**

Create `app/lib/services/injection_gate.dart`:

```dart
/// Result of feeding one output chunk through [InjectionGate].
class GateResult {
  /// Text to write to the terminal now; null while output is withheld.
  final String? emit;

  /// True exactly once: when the ready sentinel is first seen.
  final bool sendPayload;

  const GateResult({this.emit, this.sendPayload = false});
}

/// Withholds shell output between the shell-integration bootstrap write and
/// the done sentinel, so the echoed bootstrap line can be erased before it is
/// ever painted. Pure (no IO/timers) — the caller owns the timeout.
class InjectionGate {
  InjectionGate({required this.readySentinel, required this.doneSentinel});

  final String readySentinel;
  final String doneSentinel;

  final StringBuffer _held = StringBuffer();
  bool _passthrough = false;
  bool _payloadSent = false;

  bool get isHolding => !_passthrough;

  /// Size of the withheld buffer — used by the caller's over-hold guard.
  int get heldLength => _held.length;

  GateResult feed(String text) {
    if (_passthrough) return GateResult(emit: text);
    _held.write(text);
    final buf = _held.toString();
    var sendPayload = false;
    if (!_payloadSent && buf.contains(readySentinel)) {
      _payloadSent = true;
      sendPayload = true;
    }
    if (buf.contains(doneSentinel)) {
      _passthrough = true;
      _held.clear();
      return GateResult(emit: _strip(buf), sendPayload: sendPayload);
    }
    return GateResult(sendPayload: sendPayload);
  }

  /// Timeout / shell-closed path: release held text as-is and stop gating.
  String flush() {
    _passthrough = true;
    final out = _strip(_held.toString());
    _held.clear();
    return out;
  }

  String _strip(String s) =>
      s.replaceAll(readySentinel, '').replaceAll(doneSentinel, '');
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/injection_gate_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/injection_gate.dart app/test/services/injection_gate_test.dart
git commit -m "feat(shell-integration): InjectionGate withhold/scan state machine"
```

---

### Task 3: Wire gate + handshake into `SshService.openShell`

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (injection block ~lines 377–428, `openShell`)

No new unit test — there is no fake-shell harness for `openShell`; all decision
logic was tested in Tasks 1–2 and this wiring stays thin. Task 4 verifies
end-to-end behavior manually.

- [ ] **Step 1: Add import**

At the top of `app/lib/services/ssh_service.dart`, next to the existing
`shell_integration_service.dart` import, add:

```dart
import 'injection_gate.dart';
```

(If the import style in the file is package-prefixed, match it.)

- [ ] **Step 2: Replace the direct injection write with the handshake**

In `openShell`, delete the old block:

```dart
    if (siOn) {
      shell.write(Uint8List.fromList(
          shellIntegration!.buildInjectionScript().codeUnits));
    }
```

Immediately after the `initialCommand` block (where the deleted block was),
insert the state and helpers:

```dart
    // Invisible shell-integration injection (two-phase handshake; see
    // docs/superpowers/specs/2026-06-03-invisible-shell-integration-design.md).
    // Quiescence wait → bootstrap → RDY → payload (never echoed via read -rs)
    // → DONE → flush withheld output + erase the bootstrap echo in one frame.
    InjectionGate? gate;
    Timer? quiesceTimer;
    Timer? capTimer;
    Timer? doneTimer;
    var injectionStartRow = 0;
    var eraseArmed = false;

    void launchInjection() {
      if (!siOn || gate != null) return;
      quiesceTimer?.cancel();
      capTimer?.cancel();
      gate = InjectionGate(
        readySentinel: ShellIntegrationService.kReadySentinel,
        doneSentinel: ShellIntegrationService.kDoneSentinel,
      );
      injectionStartRow = session.terminal.buffer.absoluteCursorY;
      eraseArmed = true;
      shell.write(Uint8List.fromList(
          shellIntegration!.buildBootstrapLine().codeUnits));
      doneTimer = Timer(const Duration(seconds: 2), () {
        final g = gate;
        if (g == null || !g.isHolding) return;
        eraseArmed = false; // degrade: show as-is, never mis-erase
        final out = g.flush();
        if (out.isNotEmpty) session.terminal.write(out);
      });
    }

    if (siOn) {
      // Cap: inject even if the server never goes quiet (or stays silent).
      capTimer = Timer(const Duration(seconds: 3), launchInjection);
    }
```

- [ ] **Step 3: Route stdout through the gate**

Replace the body of the `shell.stdout` listener's data callback. Old:

```dart
      (data) {
        var text = utf8.convert(data);
        if (hookBus != null) {
          text = hookBus!.fireTransform(
              'terminal.output', TransformEvent(sessionId: session.id, data: text));
        }
        session.terminal.write(text);
        _recording?.writeOutput(session.id, text);
        try {
          NotificationService.instance.onTerminalData(
            text,
            sessionId: session.id,
            sessionLabel: sessionLabel,
          );
        } catch (e) {
          // Notifications must never break TTY output — log and move on.
          debugPrint('[SshService] notification handler threw: $e');
        }
      },
```

New:

```dart
      (data) {
        var text = utf8.convert(data);
        if (hookBus != null) {
          text = hookBus!.fireTransform(
              'terminal.output', TransformEvent(sessionId: session.id, data: text));
        }

        // Quiescence detection: first output seen + 300 ms of silence →
        // the prompt has rendered, safe to inject.
        if (siOn && gate == null) {
          quiesceTimer?.cancel();
          quiesceTimer = Timer(const Duration(milliseconds: 300), launchInjection);
        }

        final g = gate;
        if (g != null) {
          final wasHolding = g.isHolding;
          final r = g.feed(text);
          if (r.sendPayload) {
            shell.write(Uint8List.fromList(
                shellIntegration!.buildPayloadLine().codeUnits));
          }
          if (r.emit == null) return; // withheld
          text = r.emit!;
          if (wasHolding && !g.isHolding) {
            // DONE just arrived: write held text + erase in the same frame so
            // the bootstrap echo is never painted.
            doneTimer?.cancel();
            // Over-hold guard: a huge held buffer means real output (late
            // MOTD) landed inside the window — show it rather than erase it.
            final oversized = text.length >
                shellIntegration!.buildBootstrapLine().length * 4;
            if (eraseArmed && !oversized) {
              session.terminal.write(text);
              final rows = session.terminal.buffer.absoluteCursorY -
                  injectionStartRow;
              final erase = ShellIntegrationService.buildEraseSequence(rows);
              session.terminal.write(erase);
              text = text + erase; // recording replays the same clean view
            } else {
              session.terminal.write(text);
            }
          } else {
            session.terminal.write(text);
          }
        } else {
          session.terminal.write(text);
        }

        _recording?.writeOutput(session.id, text);
        try {
          NotificationService.instance.onTerminalData(
            text,
            sessionId: session.id,
            sessionLabel: sessionLabel,
          );
        } catch (e) {
          // Notifications must never break TTY output — log and move on.
          debugPrint('[SshService] notification handler threw: $e');
        }
      },
```

- [ ] **Step 4: Clean up timers + flush on shell close**

In the same listener, extend `onDone:`. Old:

```dart
      onDone: () {
        _onShellClosed(session);
        if (!done.isCompleted) done.complete();
      },
```

New:

```dart
      onDone: () {
        quiesceTimer?.cancel();
        capTimer?.cancel();
        doneTimer?.cancel();
        final g = gate;
        if (g != null && g.isHolding) {
          final out = g.flush();
          if (out.isNotEmpty) session.terminal.write(out);
        }
        _onShellClosed(session);
        if (!done.isCompleted) done.complete();
      },
```

- [ ] **Step 5: Analyze + full test suite**

Run: `cd app && flutter analyze && flutter test`
Expected: no analyzer issues; all tests pass. (`Timer` needs `dart:async`,
already imported in ssh_service.dart — verify.)

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat(ssh): invisible shell-integration injection via handshake + withhold/erase"
```

---

### Task 4: Manual end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Run the app and connect to a real host**

Run: `cd app && flutter run -d macos`

Connect to a saved host with shell integration enabled (zsh or bash). Verify:
1. MOTD and prompt appear immediately — no injected script text anywhere, not
   even a flash.
2. Shell integration still works: the input-bar path completion / cwd tracking
   responds after `cd` (OSC 7 events flowing).
3. `echo $__yourssh_si` prints `1` (hooks installed); `echo $__ys` prints
   nothing (unset after eval).
4. If a tmux-enabled host is available: connect with tmux on, confirm no
   visible script and integration still attaches.

- [ ] **Step 2: Fallback check (non-bash/zsh)**

On a host whose default shell is bash/zsh, run a connect where
`initialCommand` is empty, then from inside the session run `sh` manually —
this only verifies nothing new broke; the injection happens once per connect,
not per nested shell. If a dash/alpine host is available, connect and confirm
the terminal is clean (DONE-without-RDY path) and no payload junk appears.

- [ ] **Step 3: Fix anything found, re-run `flutter analyze && flutter test`, commit fixes**

---

### Task 5: Changelog

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` section, repo root)

- [ ] **Step 1: Add entry**

Under `## [Unreleased]`, in the appropriate subsection (`### Changed` or
`### Fixed`, matching the file's existing style), add:

```markdown
- Shell-integration setup script is no longer visible in the terminal on
  connect: the hook installer is delivered through a silent two-phase
  handshake (`read -rs`) and the bootstrap echo is erased before it is
  painted. Non-bash/zsh shells degrade cleanly; recordings no longer capture
  the setup script either.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): invisible shell-integration injection"
```

---

## Self-review notes

- Spec coverage: protocol builders (Task 1), gate (Task 2), quiescence/erase/
  over-hold/timeout/close wiring (Task 3), degradation + tmux verification
  (Task 4), changelog (Task 5). Recording cleanliness is covered by routing
  `_recording?.writeOutput` through the gated `text` (Task 3 Step 3).
- Type consistency: `kReadySentinel`/`kDoneSentinel` (static const on
  `ShellIntegrationService`), `buildBootstrapLine()`/`buildPayloadLine()`
  (instance), `buildEraseSequence(int)` (static) — used identically in Tasks
  1–3. `GateResult.emit`/`sendPayload`, `InjectionGate.feed/flush/isHolding/
  heldLength` match between Tasks 2 and 3.
