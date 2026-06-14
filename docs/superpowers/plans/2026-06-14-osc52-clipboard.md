# OSC 52 Clipboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let remote apps (tmux, vim) write the user's local system clipboard via the OSC 52 escape sequence, write-only, gated by a per-host opt-in that defaults off.

**Architecture:** App-layer routing (no xterm core change). OSC 52 already surfaces as `Terminal.onPrivateOSC('52', ['c', '<base64>'])`. A new pure `Osc52Clipboard` parser decodes/validates the payload; `SshService` dispatches code `52` (when the host toggle is on) to an injectable `clipboardWriter` defaulting to `Clipboard.setData`, and keeps routing codes `7`/`133` to shell integration. A per-host `SwitchListTile` in the host panel controls the opt-in.

**Tech Stack:** Flutter/Dart, `dart:convert` (base64/utf8), `flutter/services` (`Clipboard`), existing xterm fork (unchanged), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-14-osc52-clipboard-design.md`

---

## File structure

- Create: `app/lib/services/osc52_clipboard.dart` — pure parser (`Osc52Clipboard.parse` → `Osc52Result`).
- Create: `app/test/services/osc52_clipboard_test.dart` — parser unit tests.
- Modify: `app/lib/models/host.dart` — add `bool osc52Clipboard` (ctor/toJson/fromJson/copyWith).
- Create: `app/test/models/host_osc52_test.dart` — model round-trip tests.
- Modify: `app/lib/services/ssh_service.dart` — add `clipboardWriter` field, `dispatchPrivateOsc`, rewire `onPrivateOSC`.
- Create: `app/test/services/ssh_service_osc52_test.dart` — dispatch tests.
- Modify: `app/lib/widgets/host_detail_panel.dart` — `_osc52Clipboard` state + `SwitchListTile` + save wiring.
- Create: `app/test/widgets/host_detail_panel_osc52_test.dart` — toggle widget test.

All commands run from `app/` unless noted.

---

### Task 1: Pure `Osc52Clipboard` parser

**Files:**
- Create: `app/lib/services/osc52_clipboard.dart`
- Test: `app/test/services/osc52_clipboard_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/services/osc52_clipboard_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/osc52_clipboard.dart';

String b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('Osc52Clipboard.parse', () {
    test('valid write decodes base64 text', () {
      final r = Osc52Clipboard.parse(['c', b64('hello world')]);
      expect(r, isA<Osc52Write>());
      expect((r as Osc52Write).text, 'hello world');
    });

    test('empty selection target still writes', () {
      final r = Osc52Clipboard.parse(['', b64('x')]);
      expect((r as Osc52Write).text, 'x');
    });

    test('read query (?) is ignored', () {
      expect(Osc52Clipboard.parse(['c', '?']), isA<Osc52Ignored>());
    });

    test('invalid base64 is ignored', () {
      expect(Osc52Clipboard.parse(['c', '!!!not base64!!!']),
          isA<Osc52Ignored>());
    });

    test('payload over the cap is ignored', () {
      final big = base64.encode(List<int>.filled(kOsc52MaxBytes + 1, 65));
      expect(Osc52Clipboard.parse(['c', big]), isA<Osc52Ignored>());
    });

    test('non-utf8 bytes decode without throwing', () {
      final raw = base64.encode([0xff, 0xfe, 0x41]);
      expect(Osc52Clipboard.parse(['c', raw]), isA<Osc52Write>());
    });

    test('malformed arg lists are ignored', () {
      expect(Osc52Clipboard.parse(<String>[]), isA<Osc52Ignored>());
      expect(Osc52Clipboard.parse(['c']), isA<Osc52Ignored>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/osc52_clipboard_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh' ... osc52_clipboard.dart` / `Osc52Clipboard` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/services/osc52_clipboard.dart`:

```dart
import 'dart:convert';

/// Maximum decoded clipboard payload accepted from an OSC 52 write (1 MiB).
const int kOsc52MaxBytes = 1 << 20;

/// Result of parsing an OSC 52 argument list.
sealed class Osc52Result {
  const Osc52Result();
}

/// A clipboard-write request carrying the decoded [text].
class Osc52Write extends Osc52Result {
  final String text;
  const Osc52Write(this.text);
}

/// Not a write we honor: a read query (`?`), invalid base64, an oversized
/// payload, or a malformed argument list.
class Osc52Ignored extends Osc52Result {
  const Osc52Ignored();
}

class Osc52Clipboard {
  /// Parses the OSC 52 argument tail (everything after the `52` code).
  ///
  /// For `OSC 52 ; c ; <base64>` the caller hands us `['c', '<base64>']`.
  /// The selection target (first element) is ignored — desktop has a single
  /// system clipboard. Returns [Osc52Write] only for a valid, in-cap payload;
  /// every other case is [Osc52Ignored] (fail-soft — never throws).
  static Osc52Result parse(List<String> args) {
    if (args.length < 2) return const Osc52Ignored();
    final data = args.last;
    if (data == '?') return const Osc52Ignored(); // read query — never honored
    final List<int> bytes;
    try {
      bytes = base64.decode(base64.normalize(data));
    } on FormatException {
      return const Osc52Ignored();
    }
    if (bytes.length > kOsc52MaxBytes) return const Osc52Ignored();
    return Osc52Write(utf8.decode(bytes, allowMalformed: true));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/osc52_clipboard_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/thangnguyen/Projects/Personal/yourssh
git add app/lib/services/osc52_clipboard.dart app/test/services/osc52_clipboard_test.dart
git commit -m "feat(osc52): pure clipboard payload parser"
```

---

### Task 2: `Host.osc52Clipboard` field

**Files:**
- Modify: `app/lib/models/host.dart` (lines ~48, ~85, ~135, ~225, ~255, ~286 — next to `agentForwarding`)
- Test: `app/test/models/host_osc52_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/models/host_osc52_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host.osc52Clipboard', () {
    test('defaults to false', () {
      final h = Host(label: 'a', host: 'h', username: 'u');
      expect(h.osc52Clipboard, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final h = Host(label: 'a', host: 'h', username: 'u', osc52Clipboard: true);
      final back = Host.fromJson(h.toJson());
      expect(back.osc52Clipboard, isTrue);
    });

    test('absent key in json defaults to false', () {
      final json = Host(label: 'a', host: 'h', username: 'u').toJson()
        ..remove('osc52Clipboard');
      expect(Host.fromJson(json).osc52Clipboard, isFalse);
    });

    test('copyWith overrides the field', () {
      final h = Host(label: 'a', host: 'h', username: 'u');
      expect(h.copyWith(osc52Clipboard: true).osc52Clipboard, isTrue);
      expect(h.copyWith().osc52Clipboard, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/host_osc52_test.dart`
Expected: FAIL — `No named parameter with the name 'osc52Clipboard'` / `osc52Clipboard` getter undefined.

- [ ] **Step 3: Write minimal implementation**

In `app/lib/models/host.dart`:

Field — after `bool agentForwarding;` (line ~48):
```dart
  bool osc52Clipboard;
```

Constructor — after `this.agentForwarding = false,` (line ~85):
```dart
    this.osc52Clipboard = false,
```

`toJson` — after `'agentForwarding': agentForwarding,` (line ~135):
```dart
        'osc52Clipboard': osc52Clipboard,
```

`fromJson` — after `agentForwarding: (json['agentForwarding'] as bool?) ?? false,` (line ~225):
```dart
      osc52Clipboard: (json['osc52Clipboard'] as bool?) ?? false,
```

`copyWith` signature — after `bool? agentForwarding,` (line ~255):
```dart
    bool? osc52Clipboard,
```

`copyWith` body — after `agentForwarding: agentForwarding ?? this.agentForwarding,` (line ~286):
```dart
        osc52Clipboard: osc52Clipboard ?? this.osc52Clipboard,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/host_osc52_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/thangnguyen/Projects/Personal/yourssh
git add app/lib/models/host.dart app/test/models/host_osc52_test.dart
git commit -m "feat(osc52): add Host.osc52Clipboard opt-in field"
```

---

### Task 3: `SshService` OSC dispatch + injectable clipboard writer

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (imports; new field near line ~104; new method; rewire `onPrivateOSC` at lines 605-615)
- Test: `app/test/services/ssh_service_osc52_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/services/ssh_service_osc52_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

String b64(String s) => base64.encode(utf8.encode(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('code 52 with osc52 on writes decoded text to the clipboard', () {
    final svc = SshService(StorageService());
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('52', ['c', b64('copied!')],
        osc52On: true, siOn: false, sessionId: 's1', absoluteCursorY: 0);

    expect(written, ['copied!']);
  });

  test('code 52 with osc52 off does not write', () {
    final svc = SshService(StorageService());
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('52', ['c', b64('nope')],
        osc52On: false, siOn: false, sessionId: 's1', absoluteCursorY: 0);

    expect(written, isEmpty);
  });

  test('OSC 52 read query is never written', () {
    final svc = SshService(StorageService());
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('52', ['c', '?'],
        osc52On: true, siOn: false, sessionId: 's1', absoluteCursorY: 0);

    expect(written, isEmpty);
  });

  test('code 7 routes to shell integration (cwd), not the clipboard', () {
    final si = ShellIntegrationProvider();
    final svc = SshService(StorageService(), shellIntegration: si);
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('7', ['file://host/home/user'],
        osc52On: true, siOn: true, sessionId: 's1', absoluteCursorY: 0);

    expect(written, isEmpty);
    expect(si.cwdFor('s1'), '/home/user');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/ssh_service_osc52_test.dart`
Expected: FAIL — `clipboardWriter` setter / `dispatchPrivateOsc` undefined.

- [ ] **Step 3: Write minimal implementation**

In `app/lib/services/ssh_service.dart`:

(a) Add imports after line 5 (`import 'package:flutter/foundation.dart';`):
```dart
import 'package:flutter/services.dart';
import 'osc52_clipboard.dart';
```

(b) Add the injectable writer field just before the constructor (after the `sudoPasswordPrompt` field, line ~104):
```dart
  /// Writes [text] to the system clipboard for an OSC 52 write request.
  /// Injectable for tests; defaults to the platform clipboard.
  Future<void> Function(String text) clipboardWriter =
      (text) => Clipboard.setData(ClipboardData(text: text));
```

(c) Add the dispatch method (place it right after `openShell`, or anywhere in the class body — e.g. directly above `openShell`):
```dart
  /// Routes a private-OSC event. OSC 52 (when [osc52On]) writes the local
  /// clipboard; everything else falls through to shell integration when
  /// [siOn]. Extracted so the routing is unit-testable without a live session.
  @visibleForTesting
  void dispatchPrivateOsc(
    String code,
    List<String> args, {
    required bool osc52On,
    required bool siOn,
    required String sessionId,
    required int absoluteCursorY,
  }) {
    if (code == '52' && osc52On) {
      final r = Osc52Clipboard.parse(args);
      if (r is Osc52Write) clipboardWriter(r.text);
      return;
    }
    if (siOn) {
      shellIntegration?.handleOsc(sessionId, code, args, absoluteCursorY);
    }
  }
```

(d) Replace the `onPrivateOSC` wiring at lines 605-615. Current:
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
Replace with:
```dart
    final siOn = shellIntegration != null &&
        session.host.shellIntegration &&
        (isShellIntegrationEnabled?.call() ?? true);
    final osc52On = session.host.osc52Clipboard;
    if (siOn || osc52On) {
      session.terminal.onPrivateOSC = (code, args) => dispatchPrivateOsc(
            code,
            args,
            osc52On: osc52On,
            siOn: siOn,
            sessionId: session.id,
            absoluteCursorY: session.terminal.buffer.absoluteCursorY,
          );
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/ssh_service_osc52_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/thangnguyen/Projects/Personal/yourssh
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_osc52_test.dart
git commit -m "feat(osc52): dispatch OSC 52 writes to the system clipboard"
```

---

### Task 4: Host panel opt-in toggle

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart` (state field ~line 70; init ~line 110; save ~line 231; `SwitchListTile` after the Agent forwarding block ~line 803, inside the existing `if (!_isRdp)` block so RDP hides it)
- Test: `app/test/widgets/host_detail_panel_osc52_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/host_detail_panel_osc52_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
          Provider<SshService>(create: (_) => SshService(StorageService())),
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

  Host hostWith({bool osc52 = false}) =>
      Host(label: 'srv', host: '1.2.3.4', username: 'root', osc52Clipboard: osc52);

  testWidgets('toggle defaults off and saves true after switching on',
      (tester) async {
    await pumpPanel(tester, existing: hostWith());

    final toggle = find.widgetWithText(SwitchListTile, 'OSC 52 clipboard');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.osc52Clipboard, isTrue);
  });

  testWidgets('editing a host with osc52 on shows the switch on',
      (tester) async {
    await pumpPanel(tester, existing: hostWith(osc52: true));
    final toggle = find.widgetWithText(SwitchListTile, 'OSC 52 clipboard');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/host_detail_panel_osc52_test.dart`
Expected: FAIL — `osc52Clipboard` named param undefined (Task 2 supplies it) and/or no `SwitchListTile` with text `OSC 52 clipboard` found.

> Note: Task 2 must be complete first (provides `Host.osc52Clipboard`).

- [ ] **Step 3: Write minimal implementation**

In `app/lib/widgets/host_detail_panel.dart`:

(a) State field — after `bool _agentForwarding = false;` (line ~70):
```dart
  bool _osc52Clipboard = false;
```

(b) Init — after `_agentForwarding = h?.agentForwarding ?? false;` (line ~110):
```dart
    _osc52Clipboard = h?.osc52Clipboard ?? false;
```

(c) Save — in the `Host(...)` build, after `agentForwarding: !_isRdp && _agentForwarding,` (line ~231):
```dart
      osc52Clipboard: !_isRdp && _osc52Clipboard,
```

(d) UI — add a `SwitchListTile` immediately after the Agent forwarding `SwitchListTile` closing `),` at line ~803 (before the `if (_agentForwarding && ...) AgentStatusLine(...)` block), so it sits in the same SSH-only `_Card`:
```dart
                    SwitchListTile(
                      value: _osc52Clipboard,
                      onChanged: (v) => setState(() => _osc52Clipboard = v),
                      title: const Text(
                        'OSC 52 clipboard',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Let remote apps (tmux, vim) set your local clipboard. '
                        'Write-only. Off by default — only enable for hosts you '
                        'trust.',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/host_detail_panel_osc52_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/thangnguyen/Projects/Personal/yourssh
git add app/lib/widgets/host_detail_panel.dart app/test/widgets/host_detail_panel_osc52_test.dart
git commit -m "feat(osc52): per-host opt-in toggle in the host panel"
```

---

### Task 5: Verify whole feature (analyze + full test run)

**Files:** none (verification + final wrap-up)

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: No new issues in `osc52_clipboard.dart`, `host.dart`, `ssh_service.dart`, `host_detail_panel.dart` (pre-existing warnings elsewhere unchanged).

- [ ] **Step 2: Run the OSC 52 + touched-area tests together**

Run:
```bash
flutter test \
  test/services/osc52_clipboard_test.dart \
  test/models/host_osc52_test.dart \
  test/services/ssh_service_osc52_test.dart \
  test/widgets/host_detail_panel_osc52_test.dart
```
Expected: all PASS (17 tests total).

- [ ] **Step 3: Regression — host model + host panel suites**

Run:
```bash
flutter test test/models/ test/widgets/host_detail_panel_agent_forwarding_test.dart
```
Expected: PASS (the new `osc52Clipboard` field must not break existing Host round-trip / copyWith / panel tests).

- [ ] **Step 4: Manual smoke (optional, if an SSH host is available)**

Enable "OSC 52 clipboard" on a test host, connect, then on the remote run:
```bash
printf '\033]52;c;%s\007' "$(printf 'osc52 works' | base64)"
```
Paste locally → clipboard contains `osc52 works`. With the toggle off, the clipboard is unchanged.

- [ ] **Step 5: Final docs + roadmap**

Move the OSC 52 bullet from P1 (Terminal UX) into the "Already shipped" list in `docs/roadmap.md` (next version), and add a line to `docs/wiki/` per-feature docs if a Terminal user guide exists. (Defer the version bump / CHANGELOG to the normal release checklist.)

---

## Self-review

**Spec coverage:**
- Pure parser (write-only, `?` ignored, base64 decode, 1 MiB cap, UTF-8 malformed-tolerant) → Task 1. ✓
- `Host.osc52Clipboard` default-off + sync round-trip → Task 2. ✓
- `onPrivateOSC` wired when `siOn || osc52On`; code 52 → clipboard, 7/133 → shell integration; injectable `clipboardWriter` → Task 3. ✓
- Per-host toggle, SSH-only (RDP-hidden via `!_isRdp`), silent write → Task 4 + save uses `!_isRdp && _osc52Clipboard`. ✓
- Security/fail-soft (no read, drop bad/oversized) → covered by Task 1 tests + dispatch tests. ✓

**Placeholder scan:** none — every code step has full code; no TBD/TODO.

**Type consistency:** `Osc52Result`/`Osc52Write`/`Osc52Ignored`, `kOsc52MaxBytes`, `Osc52Clipboard.parse`, `clipboardWriter`, `dispatchPrivateOsc` named params (`osc52On`/`siOn`/`sessionId`/`absoluteCursorY`), `Host.osc52Clipboard` — used identically across Tasks 1-4. Save button text `SAVE ONLY` matches the existing panel harness. ✓
