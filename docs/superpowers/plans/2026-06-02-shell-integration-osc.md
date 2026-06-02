# Shell Integration (OSC 7 / OSC 133) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect remote-shell cwd, command boundaries, and exit status via injected OSC 7 / OSC 133 sequences, and surface them as cwd-in-tab, per-command gutter markers, jump-to-prompt, and cwd-aware path autocomplete.

**Architecture:** A pure `ShellIntegrationService` builds a bash/zsh prompt-hook script and parses OSC callbacks; a `ShellIntegrationProvider` holds per-session `ShellSessionState`; `SshService.openShell` injects the script and routes `Terminal.onPrivateOSC` into the provider. UI reads the provider for the tab cwd, an inline gutter overlay (Approach A), keyboard jump-to-prompt (reusing the existing `_scrollController`), and merged path suggestions in the input bar.

**Tech Stack:** Flutter, provider, xterm 4.0.0 (`onPrivateOSC`, `buffer.absoluteCursorY`), dartssh2 fork (shell + SFTP), shared_preferences. Tests: `flutter test` (run from `app/`).

**Spec:** `docs/superpowers/specs/2026-06-02-shell-integration-osc-design.md`

---

## File structure

**New**
- `app/lib/models/shell_command.dart` — one command record (boundaries + status).
- `app/lib/models/shell_session_state.dart` — per-session cwd + command list + transitions.
- `app/lib/services/shell_integration_service.dart` — pure: `ShellOscEvent`, `parseOsc`, `parseOsc7Path`, `buildInjectionScript`.
- `app/lib/providers/shell_integration_provider.dart` — `ChangeNotifier`, session-keyed state, `handleOsc`/`clear`.
- `app/lib/services/path_completion.dart` — pure path-completion planning + merge.
- `app/lib/widgets/command_gutter.dart` — gutter overlay widget + `CustomPainter`.
- Tests: `app/test/services/shell_integration_service_test.dart`, `app/test/models/shell_session_state_test.dart`, `app/test/services/path_completion_test.dart`.

**Modified**
- `app/lib/models/host.dart` — `bool shellIntegration` (default true) in fields/toJson/fromJson/copyWith.
- `app/lib/providers/settings_provider.dart` — `bool shellIntegrationEnabled` (default true).
- `app/lib/services/ssh_service.dart` — inject + `onPrivateOSC` wiring in `openShell`; cleanup in `_onShellClosed`.
- `app/lib/main.dart` — instantiate provider, register, inject into `SshService`, wire global toggle.
- `app/lib/screens/main_screen.dart` — compose cwd into the tab label (~:1395).
- `app/lib/widgets/terminal_view.dart` — gutter overlay in the build `Stack`; jump-to-prompt in `_handleKey`.
- `app/lib/widgets/terminal_input_bar.dart` — merge path suggestions; new `cwd`/`listDir` params.
- `app/lib/widgets/settings_screen.dart` — "Shell integration" toggle.
- `app/lib/widgets/host_detail_panel.dart` — per-host opt-out checkbox.

---

## PHASE 1 — Foundation (parser, models, provider, wiring, config)

### Task 1: `ShellIntegrationService` — OSC parsing

**Files:**
- Create: `app/lib/services/shell_integration_service.dart`
- Test: `app/test/services/shell_integration_service_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// app/test/services/shell_integration_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/shell_integration_service.dart';

void main() {
  final s = ShellIntegrationService();

  group('parseOsc7Path', () {
    test('strips scheme + host, decodes percent-encoding', () {
      expect(ShellIntegrationService.parseOsc7Path('file://myhost/home/u/my%20proj'),
          '/home/u/my proj');
    });
    test('handles empty host (file:///path)', () {
      expect(ShellIntegrationService.parseOsc7Path('file:///var/log'), '/var/log');
    });
    test('rejects non-file urls', () {
      expect(ShellIntegrationService.parseOsc7Path('http://x/y'), isNull);
    });
  });

  group('parseOsc', () {
    test('OSC 7 -> cwd', () {
      final e = s.parseOsc('7', ['file://h/srv/app'])!;
      expect(e.kind, ShellOscKind.cwd);
      expect(e.cwd, '/srv/app');
    });
    test('OSC 133;A -> promptStart', () {
      expect(s.parseOsc('133', ['A'])!.kind, ShellOscKind.promptStart);
    });
    test('OSC 133;C -> exec', () {
      expect(s.parseOsc('133', ['C'])!.kind, ShellOscKind.exec);
    });
    test('OSC 133;D;0 -> finished exit 0', () {
      final e = s.parseOsc('133', ['D', '0'])!;
      expect(e.kind, ShellOscKind.finished);
      expect(e.exitCode, 0);
    });
    test('OSC 133;D (no code) -> finished null exit', () {
      expect(s.parseOsc('133', ['D'])!.exitCode, isNull);
    });
    test('OSC 133;B and unknown -> null', () {
      expect(s.parseOsc('133', ['B']), isNull);
      expect(s.parseOsc('133', ['Z']), isNull);
      expect(s.parseOsc('9', ['x']), isNull);
      expect(s.parseOsc('133', const []), isNull);
    });
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `cd app && flutter test test/services/shell_integration_service_test.dart`
Expected: FAIL (target of URI doesn't exist / undefined).

- [ ] **Step 3: Implement**

```dart
// app/lib/services/shell_integration_service.dart

enum ShellOscKind { cwd, promptStart, exec, finished }

class ShellOscEvent {
  final ShellOscKind kind;
  final String? cwd;
  final int? exitCode;
  const ShellOscEvent.cwd(this.cwd)
      : kind = ShellOscKind.cwd, exitCode = null;
  const ShellOscEvent.promptStart()
      : kind = ShellOscKind.promptStart, cwd = null, exitCode = null;
  const ShellOscEvent.exec()
      : kind = ShellOscKind.exec, cwd = null, exitCode = null;
  const ShellOscEvent.finished(this.exitCode)
      : kind = ShellOscKind.finished, cwd = null;
}

/// Pure helpers for shell integration. No Flutter / IO deps so it unit-tests
/// without a Terminal or SSH connection.
class ShellIntegrationService {
  /// Parse an `OSC 7 ; file://host/path` URL into a decoded absolute path.
  /// Returns null for anything that isn't a file URL with a path.
  static String? parseOsc7Path(String url) {
    if (!url.startsWith('file://')) return null;
    final rest = url.substring('file://'.length); // host/path  or  /path
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final raw = rest.substring(slash);
    try {
      return Uri.decodeFull(raw);
    } catch (_) {
      return raw;
    }
  }

  /// Map an xterm `onPrivateOSC(code, args)` callback to a typed event,
  /// or null when irrelevant/malformed.
  ShellOscEvent? parseOsc(String code, List<String> args) {
    if (code == '7') {
      if (args.isEmpty) return null;
      final path = parseOsc7Path(args.first);
      return path == null ? null : ShellOscEvent.cwd(path);
    }
    if (code == '133') {
      if (args.isEmpty) return null;
      switch (args.first) {
        case 'A':
          return const ShellOscEvent.promptStart();
        case 'C':
          return const ShellOscEvent.exec();
        case 'D':
          return ShellOscEvent.finished(
              args.length > 1 ? int.tryParse(args[1]) : null);
        default:
          return null;
      }
    }
    return null;
  }

  /// Single-line bash/zsh setup written to the shell on connect. Guarded
  /// (`__yourssh_si`) so a re-source is a no-op; appends to PROMPT_COMMAND /
  /// precmd/preexec arrays rather than overwriting; silent on other shells.
  String buildInjectionScript() {
    const zsh = r'''__ys_osc7(){ printf '\033]7;file://%s%s\a' "$HOST" "${PWD}"; }; __ys_pre(){ printf '\033]133;A\a'; __ys_osc7; }; __ys_exec(){ printf '\033]133;C\a'; }; __ys_post(){ printf '\033]133;D;%s\a' "$?"; }; precmd_functions+=(__ys_post __ys_pre); preexec_functions+=(__ys_exec); PS1="%{$(printf '\033]133;B\a')%}$PS1"''';
    const bash = r'''__ys_post(){ local e=$?; printf '\033]133;D;%s\a' "$e"; printf '\033]133;A\a'; printf '\033]7;file://%s%s\a' "$HOSTNAME" "${PWD}"; }; PROMPT_COMMAND="__ys_post;${PROMPT_COMMAND:-}"; trap 'printf "\033]133;C\a"' DEBUG; PS1="$PS1\[$(printf '\033]133;B\a')\]"''';
    return 'if [ -z "\$__yourssh_si" ]; then __yourssh_si=1; '
        'if [ -n "\$ZSH_VERSION" ]; then $zsh; '
        'elif [ -n "\$BASH_VERSION" ]; then $bash; fi; fi\n';
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `cd app && flutter test test/services/shell_integration_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/shell_integration_service.dart app/test/services/shell_integration_service_test.dart
git commit -m "feat(shell-integration): OSC 7/133 parser + injection script"
```

---

### Task 2: `buildInjectionScript` shape test

**Files:**
- Modify: `app/test/services/shell_integration_service_test.dart`

- [ ] **Step 1: Add failing test (append inside main())**

```dart
  group('buildInjectionScript', () {
    final script = s.buildInjectionScript();
    test('is single-line and guarded + idempotent', () {
      expect('\n'.allMatches(script).length, 1); // only trailing newline
      expect(script, contains(r'$__yourssh_si'));
    });
    test('covers bash and zsh branches', () {
      expect(script, contains(r'$ZSH_VERSION'));
      expect(script, contains(r'$BASH_VERSION'));
      expect(script, contains('precmd_functions+=('));
      expect(script, contains('PROMPT_COMMAND="__ys_post;'));
      expect(script, contains("trap 'printf \"\\033]133;C\\a\"' DEBUG"));
    });
    test('emits all OSC markers', () {
      for (final m in [r']133;A', r']133;B', r']133;C', r']133;D', r']7;file://']) {
        expect(script, contains(m));
      }
    });
  });
```

- [ ] **Step 2: Run** — `cd app && flutter test test/services/shell_integration_service_test.dart` → some new asserts may fail if string drifted. Adjust the script/test until green (no impl change expected if Task 1 string is intact).

- [ ] **Step 3: Commit**

```bash
git add app/test/services/shell_integration_service_test.dart
git commit -m "test(shell-integration): pin injection script shape"
```

---

### Task 3: `ShellCommand` + `ShellSessionState`

**Files:**
- Create: `app/lib/models/shell_command.dart`, `app/lib/models/shell_session_state.dart`
- Test: `app/test/models/shell_session_state_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// app/test/models/shell_session_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/shell_session_state.dart';

void main() {
  test('A -> C -> D lifecycle on the latest command', () {
    final st = ShellSessionState();
    st.setCwd('/srv/app');
    st.onPromptStart(42);
    expect(st.commands.single.promptLine, 42);
    expect(st.commands.single.cwd, '/srv/app');
    expect(st.commands.single.isRunning, isFalse); // not yet exec'd
    st.onExec();
    expect(st.commands.single.isRunning, isTrue);
    st.onFinished(0);
    expect(st.commands.single.isRunning, isFalse);
    expect(st.commands.single.succeeded, isTrue);
    expect(st.commands.single.duration, isNotNull);
  });

  test('D finalizes previous, A opens next', () {
    final st = ShellSessionState()
      ..onPromptStart(1)..onExec();
    st.onFinished(1);          // cmd #1 fails
    st.onPromptStart(5);       // next prompt
    expect(st.commands.length, 2);
    expect(st.commands[0].succeeded, isFalse);
    expect(st.commands[1].promptLine, 5);
  });

  test('finished/exec with no pending command is a no-op', () {
    final st = ShellSessionState();
    expect(() { st.onFinished(0); st.onExec(); }, returnsNormally);
    expect(st.commands, isEmpty);
  });

  test('command list is capped', () {
    final st = ShellSessionState();
    for (var i = 0; i < 600; i++) { st.onPromptStart(i); }
    expect(st.commands.length, 500);
    expect(st.commands.first.promptLine, 100); // oldest dropped
  });
}
```

- [ ] **Step 2: Run, verify fail** — `cd app && flutter test test/models/shell_session_state_test.dart` → FAIL (undefined).

- [ ] **Step 3: Implement**

```dart
// app/lib/models/shell_command.dart
class ShellCommand {
  final int promptLine;   // absolute buffer line of the prompt (for gutter/jump)
  final String? cwd;
  String? text;           // best-effort, optional
  DateTime? startedAt;    // set at exec (OSC 133;C)
  DateTime? finishedAt;   // set at finished (OSC 133;D)
  int? exitCode;

  ShellCommand({required this.promptLine, this.cwd});

  bool get isRunning => startedAt != null && finishedAt == null;
  bool? get succeeded => exitCode == null ? null : exitCode == 0;
  Duration? get duration => (startedAt != null && finishedAt != null)
      ? finishedAt!.difference(startedAt!)
      : null;
}
```

```dart
// app/lib/models/shell_session_state.dart
import 'shell_command.dart';

class ShellSessionState {
  static const _maxCommands = 500;

  String? cwd;
  final List<ShellCommand> commands = [];

  ShellCommand? get _pending => commands.isEmpty ? null : commands.last;

  void setCwd(String path) => cwd = path;

  void onPromptStart(int promptLine) {
    commands.add(ShellCommand(promptLine: promptLine, cwd: cwd));
    if (commands.length > _maxCommands) commands.removeAt(0);
  }

  void onExec() => _pending?.startedAt = DateTime.now();

  void onFinished(int? exitCode) {
    final c = _pending;
    if (c == null) return;
    c.finishedAt = DateTime.now();
    c.exitCode = exitCode;
  }
}
```

- [ ] **Step 4: Run, verify pass** — `cd app && flutter test test/models/shell_session_state_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/shell_command.dart app/lib/models/shell_session_state.dart app/test/models/shell_session_state_test.dart
git commit -m "feat(shell-integration): ShellCommand + ShellSessionState"
```

---

### Task 4: `ShellIntegrationProvider`

**Files:**
- Create: `app/lib/providers/shell_integration_provider.dart`
- Test: add to `app/test/models/shell_session_state_test.dart` (or a new provider test)

- [ ] **Step 1: Write failing test** — new file `app/test/providers/shell_integration_provider_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';

void main() {
  test('routes OSC events into per-session state + notifies', () {
    final p = ShellIntegrationProvider();
    var notifications = 0;
    p.addListener(() => notifications++);

    p.handleOsc('s1', '7', ['file://h/srv'], 0);
    p.handleOsc('s1', '133', ['A'], 7);
    p.handleOsc('s1', '133', ['C'], 7);
    p.handleOsc('s1', '133', ['D', '0'], 7);

    expect(p.cwdFor('s1'), '/srv');
    final st = p.maybeStateFor('s1')!;
    expect(st.commands.single.promptLine, 7);
    expect(st.commands.single.succeeded, isTrue);
    expect(notifications, 4);
  });

  test('ignored OSC does not create state or notify', () {
    final p = ShellIntegrationProvider();
    var notifications = 0;
    p.addListener(() => notifications++);
    p.handleOsc('s1', '133', ['B'], 0); // B is a no-op
    expect(p.maybeStateFor('s1'), isNull);
    expect(notifications, 0);
  });

  test('clear removes state', () {
    final p = ShellIntegrationProvider()..handleOsc('s1', '7', ['file://h/x'], 0);
    p.clear('s1');
    expect(p.maybeStateFor('s1'), isNull);
  });
}
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement**

```dart
// app/lib/providers/shell_integration_provider.dart
import 'package:flutter/foundation.dart';
import '../models/shell_session_state.dart';
import '../services/shell_integration_service.dart';

class ShellIntegrationProvider extends ChangeNotifier {
  ShellIntegrationProvider([ShellIntegrationService? service])
      : _service = service ?? ShellIntegrationService();

  final ShellIntegrationService _service;
  final Map<String, ShellSessionState> _states = {};

  ShellSessionState? maybeStateFor(String id) => _states[id];
  String? cwdFor(String id) => _states[id]?.cwd;

  String buildInjectionScript() => _service.buildInjectionScript();

  /// [absoluteCursorY] is `terminal.buffer.absoluteCursorY` captured by the
  /// caller at marker time (kept out of this class so it stays testable).
  void handleOsc(String sessionId, String code, List<String> args,
      int absoluteCursorY) {
    final ev = _service.parseOsc(code, args);
    if (ev == null) return;
    final st = _states.putIfAbsent(sessionId, ShellSessionState.new);
    switch (ev.kind) {
      case ShellOscKind.cwd:
        st.setCwd(ev.cwd!);
      case ShellOscKind.promptStart:
        st.onPromptStart(absoluteCursorY);
      case ShellOscKind.exec:
        st.onExec();
      case ShellOscKind.finished:
        st.onFinished(ev.exitCode);
    }
    notifyListeners();
  }

  void clear(String sessionId) {
    if (_states.remove(sessionId) != null) notifyListeners();
  }
}
```

- [ ] **Step 4: Run, verify pass.**

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/shell_integration_provider.dart app/test/providers/shell_integration_provider_test.dart
git commit -m "feat(shell-integration): ShellIntegrationProvider"
```

---

### Task 5: `Host.shellIntegration` field

**Files:**
- Modify: `app/lib/models/host.dart`

- [ ] **Step 1: Add field + JSON + copyWith.** In the field list after `jumpHostId`:

```dart
  String? jumpHostId;
  bool shellIntegration;
```

Constructor param (after `this.jumpHostId,`): `this.shellIntegration = true,`

In `toJson()` add: `'shellIntegration': shellIntegration,`

In `fromJson` constructor call add: `shellIntegration: (json['shellIntegration'] as bool?) ?? true,`

In `copyWith` signature add `bool? shellIntegration,` and in the body `shellIntegration: shellIntegration ?? this.shellIntegration,`.

- [ ] **Step 2: Verify analyze** — `cd app && flutter analyze lib/models/host.dart` → no new errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/host.dart
git commit -m "feat(shell-integration): per-host shellIntegration opt-out (default on)"
```

---

### Task 6: `SettingsProvider.shellIntegrationEnabled`

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`

- [ ] **Step 1:** Add field after `commandNotificationsEnabled`:

```dart
  bool shellIntegrationEnabled = true;
```

In `_load()`: `shellIntegrationEnabled = prefs.getBool('shellIntegrationEnabled') ?? true;`

In `save({...})` params add `bool? shellIntegrationEnabled,`; body add
`if (shellIntegrationEnabled != null) this.shellIntegrationEnabled = shellIntegrationEnabled;`
and persist `await prefs.setBool('shellIntegrationEnabled', this.shellIntegrationEnabled);`.

- [ ] **Step 2: Verify** — `cd app && flutter analyze lib/providers/settings_provider.dart`.

- [ ] **Step 3: Commit**

```bash
git add app/lib/providers/settings_provider.dart
git commit -m "feat(shell-integration): global shellIntegrationEnabled setting"
```

---

### Task 7: Wire injection + `onPrivateOSC` into `SshService`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1:** Add import + fields. After `import 'storage_service.dart';` add:
`import '../providers/shell_integration_provider.dart';`

Change the constructor and fields:

```dart
  final HookBus? hookBus;
  final ShellIntegrationProvider? shellIntegration;
  /// Global on/off, read from SettingsProvider in main.dart. null => treat as on.
  bool Function()? isShellIntegrationEnabled;
  ...
  SshService(this._storage, {this.hookBus, this.shellIntegration});
```

- [ ] **Step 2:** In `openShell`, right after `_shellToHost[session.id] = session.host.id;` (line ~337), compute the gate and set the OSC handler **before** the stdout listener:

```dart
    final siOn = shellIntegration != null &&
        session.host.shellIntegration &&
        (isShellIntegrationEnabled?.call() ?? true);
    if (siOn) {
      session.terminal.onPrivateOSC = (code, args) => shellIntegration!.handleOsc(
            session.id,
            code,
            args,
            session.terminal.buffer.absoluteCursorY,
          );
    }
```

- [ ] **Step 3:** Inject the script after the tmux / initialCommand writes (after line ~355):

```dart
    if (siOn) {
      shell.write(Uint8List.fromList(
          shellIntegration!.buildInjectionScript().codeUnits));
    }
```

- [ ] **Step 4:** In `_onShellClosed`, after `session.terminal.onResize = null;` add:

```dart
    session.terminal.onPrivateOSC = null;
    shellIntegration?.clear(session.id);
```

- [ ] **Step 5: Verify** — `cd app && flutter analyze lib/services/ssh_service.dart` → no new errors.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat(shell-integration): inject script + route onPrivateOSC in openShell"
```

---

### Task 8: Register provider + global toggle in `main.dart`

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1:** Find where `SshService` is constructed and where `SettingsProvider` exists. Create the provider before `SshService`:

```dart
final shellIntegrationProvider = ShellIntegrationProvider();
```

Pass it into `SshService(storage, hookBus: hookBus, shellIntegration: shellIntegrationProvider);`
and wire the global toggle once `settingsProvider` is available:

```dart
sshService.isShellIntegrationEnabled = () => settingsProvider.shellIntegrationEnabled;
```

Add `ChangeNotifierProvider.value(value: shellIntegrationProvider),` to the `MultiProvider` list, plus the import.

- [ ] **Step 2: Verify** — `cd app && flutter analyze lib/main.dart`.

- [ ] **Step 3: Run app smoke** — `cd app && flutter run -d macos` (or current platform), connect to a bash/zsh host; confirm no garbage prints and the app is stable. (Manual.)

- [ ] **Step 4: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(shell-integration): register provider + wire global toggle"
```

---

## PHASE 2 — cwd in tab title + status

### Task 9: Compose cwd into the tab label

**Files:**
- Modify: `app/lib/screens/main_screen.dart` (~:1395, the tab label `Text`)

- [ ] **Step 1:** Read the tab builder around `widget.session.tabLabel` (~:1395). Replace the displayed string with a composition that appends the cwd basename when present and no custom label is set:

```dart
// near the tab Text widget
final cwd = context.watch<ShellIntegrationProvider>().cwdFor(widget.session.id);
final base = widget.session.tabLabel;
final label = (widget.session.customLabel == null && cwd != null && cwd.isNotEmpty)
    ? '$base · ${cwd.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '/'}'
    : base;
```

Use `label` in the `Text(...)`. Add the import for `ShellIntegrationProvider`. If the tab widget isn't already a `context.watch` consumer, ensure it rebuilds (it is a `StatefulWidget` row item; `context.watch` inside `build` is sufficient).

- [ ] **Step 2: Verify** — `cd app && flutter analyze lib/screens/main_screen.dart`.

- [ ] **Step 3: Manual check** — connect to a bash host, `cd /tmp`, confirm the tab shows `… · tmp` and full path appears in the existing tab tooltip if present (leave tooltip as-is for v1).

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat(shell-integration): show cwd basename in session tab"
```

---

## PHASE 3 — Gutter markers + jump-to-prompt

### Task 10: Command gutter overlay widget

**Files:**
- Create: `app/lib/widgets/command_gutter.dart`

- [ ] **Step 1: Implement** (visual; verified manually — no unit test for the painter):

```dart
// app/lib/widgets/command_gutter.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/shell_command.dart';
import '../providers/shell_integration_provider.dart';

/// Thin left strip drawing a status dot next to each command's prompt line.
/// Aligns to the same line→pixel math the terminal scroll uses
/// (lineHeight = fontSize * 1.35) and repaints as the view scrolls.
class CommandGutter extends StatelessWidget {
  const CommandGutter({
    super.key,
    required this.sessionId,
    required this.scrollController,
    required this.lineHeight,
    this.width = 8,
    this.onJumpTo,
  });

  final String sessionId;
  final ScrollController scrollController;
  final double lineHeight;
  final double width;
  final void Function(int promptLine)? onJumpTo;

  @override
  Widget build(BuildContext context) {
    final commands =
        context.watch<ShellIntegrationProvider>().maybeStateFor(sessionId)?.commands ??
            const <ShellCommand>[];
    if (commands.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: AnimatedBuilder(
        animation: scrollController,
        builder: (context, _) {
          final offset =
              scrollController.hasClients ? scrollController.offset : 0.0;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: onJumpTo == null
                ? null
                : (d) {
                    final y = d.localPosition.dy + offset;
                    final line = (y / lineHeight).round();
                    ShellCommand? best;
                    for (final c in commands) {
                      if (best == null ||
                          (c.promptLine - line).abs() <
                              (best.promptLine - line).abs()) {
                        best = c;
                      }
                    }
                    if (best != null) onJumpTo!(best.promptLine);
                  },
            child: CustomPaint(
              painter: _GutterPainter(commands, offset, lineHeight),
              size: Size(width, double.infinity),
            ),
          );
        },
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter(this.commands, this.scrollOffset, this.lineHeight);
  final List<ShellCommand> commands;
  final double scrollOffset;
  final double lineHeight;

  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _grey = Color(0xFF6B7280);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final c in commands) {
      final y = c.promptLine * lineHeight - scrollOffset + lineHeight / 2;
      if (y < -lineHeight || y > size.height + lineHeight) continue;
      paint.color = switch (c.succeeded) {
        true => _green,
        false => _red,
        null => _grey,
      };
      canvas.drawCircle(Offset(size.width / 2, y), 3, paint);
    }
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.commands.length != commands.length ||
      old.lineHeight != lineHeight;
}
```

- [ ] **Step 2: Verify** — `cd app && flutter analyze lib/widgets/command_gutter.dart`.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/command_gutter.dart
git commit -m "feat(shell-integration): command gutter overlay widget"
```

---

### Task 11: Mount gutter + jump-to-prompt in terminal view

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1:** Add imports (`command_gutter.dart`, `dart:io` already present for Platform). Add a jump helper to the state class:

```dart
  void _jumpToPrompt(int direction) {
    final st = context.read<ShellIntegrationProvider>().maybeStateFor(widget.session.id);
    if (st == null || st.commands.isEmpty || !_scrollController.hasClients) return;
    final lineHeight = context.read<SettingsProvider>().fontSize * 1.35;
    final currentLine = _scrollController.offset / lineHeight;
    final lines = st.commands.map((c) => c.promptLine).toList()..sort();
    int? target;
    if (direction < 0) {
      for (final l in lines) { if (l < currentLine - 0.5) target = l; }
    } else {
      for (final l in lines) { if (l > currentLine + 0.5) { target = l; break; } }
    }
    if (target == null) return;
    final offset = (target * lineHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }
```

- [ ] **Step 2:** In `_handleKey`, where `ctrl`/`meta`/`key` are known, add (before the raw-input fallthrough):

```dart
    final jumpMod = Platform.isMacOS ? meta : ctrl;
    if (jumpMod && key == LogicalKeyboardKey.arrowUp) {
      _jumpToPrompt(-1);
      return KeyEventResult.handled;
    }
    if (jumpMod && key == LogicalKeyboardKey.arrowDown) {
      _jumpToPrompt(1);
      return KeyEventResult.handled;
    }
```

- [ ] **Step 3:** In `build()`'s `Stack` (after the `TerminalView`), add the gutter:

```dart
        Positioned(
          left: 0, top: 0, bottom: 0,
          child: CommandGutter(
            sessionId: widget.session.id,
            scrollController: _scrollController,
            lineHeight: settings.fontSize * 1.35,
            onJumpTo: (line) {
              if (!_scrollController.hasClients) return;
              final offset = (line * settings.fontSize * 1.35)
                  .clamp(0.0, _scrollController.position.maxScrollExtent);
              _scrollController.animateTo(offset,
                  duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
            },
          ),
        ),
```

- [ ] **Step 4: Verify** — `cd app && flutter analyze lib/widgets/terminal_view.dart`.

- [ ] **Step 5: Manual check** — run several commands (mix exit 0 / non-zero), confirm green/red dots align to prompts, scroll keeps them aligned, `Cmd/Ctrl+↑/↓` jumps between prompts, tapping a dot scrolls to it.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat(shell-integration): mount gutter + jump-to-prompt shortcuts"
```

---

## PHASE 4 — cwd-aware autocomplete

### Task 12: Pure path-completion helpers

**Files:**
- Create: `app/lib/services/path_completion.dart`
- Test: `app/test/services/path_completion_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// app/test/services/path_completion_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/path_completion.dart';

void main() {
  group('planPathCompletion', () {
    test('absolute path token -> dir + prefix', () {
      final p = planPathCompletion('cat /etc/ho', '/home/u')!;
      expect(p.dir, '/etc');
      expect(p.prefix, 'ho');
    });
    test('relative token resolves against cwd', () {
      final p = planPathCompletion('cd sub/fo', '/home/u')!;
      expect(p.dir, '/home/u/sub');
      expect(p.prefix, 'fo');
    });
    test('bare path-command + no slash lists cwd', () {
      final p = planPathCompletion('cd ', '/home/u')!;
      expect(p.dir, '/home/u');
      expect(p.prefix, '');
    });
    test('non-path command without slash -> null', () {
      expect(planPathCompletion('echo hello', '/home/u'), isNull);
    });
    test('relative token but no cwd -> null', () {
      expect(planPathCompletion('cd sub/fo', null), isNull);
    });
  });

  group('mergePathSuggestions', () {
    test('replaces the path token, filters by prefix, keeps the command', () {
      final out = mergePathSuggestions(
        'cat /etc/ho',
        const PathPlan(dir: '/etc', prefix: 'ho'),
        ['hostname', 'hosts/', 'group'],
      );
      expect(out, ['cat /etc/hostname', 'cat /etc/hosts/']);
    });
  });
}
```

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement**

```dart
// app/lib/services/path_completion.dart

class PathPlan {
  final String dir;     // remote directory to list
  final String prefix;  // filter applied to entries
  const PathPlan({required this.dir, required this.prefix});
}

const _pathCommands = {
  'cd', 'ls', 'cat', 'less', 'more', 'tail', 'head',
  'cp', 'mv', 'rm', 'vim', 'vi', 'nano', 'source', 'touch', 'mkdir',
};

/// Decide whether the current input wants path completion, and if so which
/// remote dir to list and what prefix to filter by. Returns null when the
/// input isn't a path context or a relative path can't be resolved (no cwd).
PathPlan? planPathCompletion(String input, String? cwd) {
  if (input.isEmpty) return null;
  final parts = input.split(' ');
  final first = parts.first;
  final token = parts.length == 1 ? '' : parts.last; // arg token (may be '')
  final isPathCmd = _pathCommands.contains(first);
  final looksPath = token.contains('/') || token.startsWith('.') || token.startsWith('~');
  if (parts.length == 1) return null;        // still typing the command word
  if (!isPathCmd && !looksPath) return null;

  final slash = token.lastIndexOf('/');
  final dirPart = slash < 0 ? '' : token.substring(0, slash + 1);
  final prefix = slash < 0 ? token : token.substring(slash + 1);

  String? dir;
  if (dirPart.startsWith('/')) {
    dir = dirPart.isEmpty ? '/' : _trimSlash(dirPart);
  } else {
    if (cwd == null) return null;
    dir = dirPart.isEmpty ? cwd : '$cwd/${_trimSlash(dirPart)}';
  }
  return PathPlan(dir: dir.isEmpty ? '/' : dir, prefix: prefix);
}

String _trimSlash(String s) =>
    s.length > 1 && s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Build full-command suggestions by completing the path token with each
/// matching directory entry (entries may carry a trailing '/').
List<String> mergePathSuggestions(String input, PathPlan plan, List<String> entries) {
  final slash = input.lastIndexOf('/');
  final head = slash < 0 ? '${input.substring(0, input.length - plan.prefix.length)}' : input.substring(0, slash + 1);
  return entries
      .where((e) => e.startsWith(plan.prefix))
      .map((e) => '$head$e')
      .take(8)
      .toList();
}
```

- [ ] **Step 4: Run, verify pass.** Adjust `mergePathSuggestions` head computation if a case fails (the test pins the contract).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/path_completion.dart app/test/services/path_completion_test.dart
git commit -m "feat(shell-integration): pure path-completion planning + merge"
```

---

### Task 13: Remote dir listing on `SshService`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1:** Add a cached-SFTP listing method (reuse one SFTP client per host for completion). Near `openSftp` (~:493):

```dart
  final Map<String, SftpClient> _completionSftp = {};

  /// List a remote directory for path autocomplete. Reuses a cached SFTP
  /// client per host. Returns entry names (dirs carry a trailing '/').
  /// Returns an empty list on any failure — completion must never throw.
  Future<List<String>> listDirectory(Host host, String path) async {
    try {
      final sftp = _completionSftp[host.id] ??= await openSftp(host);
      final items = await sftp.listdir(path.isEmpty ? '.' : path);
      return items
          .map((e) => e.filename + (e.attr.isDirectory ? '/' : ''))
          .where((n) => n != './' && n != '../')
          .toList();
    } catch (e) {
      debugPrint('[SshService] listDirectory failed for $path: $e');
      return const [];
    }
  }
```

> Verify against existing SFTP usage (`SftpPanelProvider`) for the exact `SftpName` accessor (`filename` / `attr.isDirectory`) and align if the fork differs. Drop the cached client in `disconnect`/`_onShellClosed` cleanup (`_completionSftp.remove(host.id)`).

- [ ] **Step 2: Verify** — `cd app && flutter analyze lib/services/ssh_service.dart`.

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat(shell-integration): SshService.listDirectory for path completion"
```

---

### Task 14: Merge path suggestions in the input bar

**Files:**
- Modify: `app/lib/widgets/terminal_input_bar.dart`, and its construction site (likely `app/lib/widgets/terminal_view.dart` or `main_screen.dart`).

- [ ] **Step 1:** Add params to `TerminalInputBar`:

```dart
  final String? cwd;
  final Future<List<String>> Function(String dir)? listDir;
```
(in the constructor too, both optional.)

- [ ] **Step 2:** Replace `_onTextChanged` with a debounced path-aware version:

```dart
  Timer? _debounce;
  int _completionSeq = 0;

  void _onTextChanged() {
    final text = _controller.text;
    final history = context.read<CommandHistoryProvider>();
    final plan = planPathCompletion(text, widget.cwd);
    if (plan == null || widget.listDir == null) {
      setState(() {
        _suggestions = history.suggestions(widget.sessionId, text);
        _selectedIndex = -1;
      });
      return;
    }
    _debounce?.cancel();
    final seq = ++_completionSeq;
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final entries = await widget.listDir!(plan.dir);
      if (!mounted || seq != _completionSeq) return; // stale
      setState(() {
        _suggestions = mergePathSuggestions(text, plan, entries);
        _selectedIndex = -1;
      });
    });
  }
```
Add imports (`dart:async`, `../services/path_completion.dart`) and cancel `_debounce` in `dispose()`.

- [ ] **Step 3:** At the construction site, pass `cwd` + `listDir`. Where `TerminalInputBar(sessionId: …)` is built, add:

```dart
  cwd: context.watch<ShellIntegrationProvider>().cwdFor(session.id),
  listDir: (dir) => sshService.listDirectory(session.host, dir),
```
(obtain `sshService` via `context.read<SshService>()` if it's a provider, or the existing reference at that site).

- [ ] **Step 4: Verify** — `cd app && flutter analyze lib/widgets/terminal_input_bar.dart`.

- [ ] **Step 5: Manual check** — open the input bar, type `cd /et` → suggestions include `/etc/`; `cd ` lists cwd entries; non-path commands still show history.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/terminal_input_bar.dart app/lib/widgets/terminal_view.dart
git commit -m "feat(shell-integration): cwd-aware path completion in input bar"
```

---

## PHASE 5 — Settings UI + finalize

### Task 15: Settings + host opt-out toggles

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`, `app/lib/widgets/host_detail_panel.dart`

- [ ] **Step 1:** In `settings_screen.dart` terminal section, add a `SwitchListTile` bound to `settings.shellIntegrationEnabled`, calling `context.read<SettingsProvider>().save(shellIntegrationEnabled: v)`.

- [ ] **Step 2:** In `host_detail_panel.dart`, add a checkbox/switch for `host.shellIntegration` writing back via the host edit flow (mirror how `autoRecord` is edited).

- [ ] **Step 3: Verify** — `cd app && flutter analyze`.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/settings_screen.dart app/lib/widgets/host_detail_panel.dart
git commit -m "feat(shell-integration): settings toggle + per-host opt-out UI"
```

---

### Task 16: Full suite + analyze + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1:** `cd app && flutter analyze` → no new errors.
- [ ] **Step 2:** `cd app && flutter test` → all pass.
- [ ] **Step 3:** Add an `### Added` entry under `[Unreleased]` in `CHANGELOG.md` describing shell integration (cwd-in-tab, gutter status markers, jump-to-prompt, cwd-aware completion; bash/zsh, opt-out).
- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): shell integration (OSC 7/133)"
```

---

## Self-review notes

- **Spec coverage:** injection policy + bash/zsh guard (Task 1/7), onPrivateOSC capture (Task 7), cwd-in-tab (Task 9), gutter markers (Task 10/11), jump-to-prompt (Task 11), autocomplete (Task 12-14), settings + opt-out (Task 5/6/15), edge cases (no-op transitions Task 3, clear on close Task 7, listDirectory never throws Task 13). ✓
- **Deferred (spec "out of scope"):** command text over OSC (best-effort only; `ShellCommand.text` left unset in v1 — not surfaced), xterm fork, timeline panel, DEBUG-trap fire-once guard. ✓
- **Type consistency:** `ShellOscKind`, `ShellOscEvent`, `ShellSessionState.{setCwd,onPromptStart,onExec,onFinished}`, `ShellIntegrationProvider.{handleOsc,clear,cwdFor,maybeStateFor,buildInjectionScript}`, `PathPlan{dir,prefix}`, `planPathCompletion`, `mergePathSuggestions`, `SshService.listDirectory` consistent across tasks. ✓
- **Risk to verify at execution:** SFTP `SftpName.filename`/`attr.isDirectory` accessor names (Task 13); the exact `TerminalInputBar` construction site (Task 14); `_handleKey` modifier variable names in `terminal_view.dart` (Task 11).
