# Terminal Emulation Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global "Terminal emulation type" setting (`xterm-256color` / `xterm` / `linux` / `vt100`) that controls the TERM sent in the SSH PTY request.

**Architecture:** Follows the existing `tmuxEnabled` settings → callback → service pattern: `SettingsProvider` persists the value, `main.dart` wires a callback into `SessionProvider`, which passes it to `SshService.openShell`, which forwards it as `SSHPtyConfig.type`. SSH-only — the local shell keeps its hardcoded `TERM=xterm-256color`.

**Tech Stack:** Flutter (provider, shared_preferences), local dartssh2 fork (already supports `SSHPtyConfig.type`).

**Spec:** `docs/superpowers/specs/2026-06-05-terminal-emulation-type-design.md`

---

### Task 1: `SettingsProvider.terminalType` (TDD)

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Test: `app/test/settings_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `app/test/settings_provider_test.dart` (before the closing `}`), following the existing `terminalFont` test trio:

```dart
  test('terminalType defaults to xterm-256color', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalType, 'xterm-256color');
  });

  test('save persists terminalType', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(terminalType: 'vt100');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('terminalType'), 'vt100');
    expect(provider.terminalType, 'vt100');
  });

  test('loads persisted terminalType on init', () async {
    SharedPreferences.setMockInitialValues({'terminalType': 'linux'});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalType, 'linux');
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/settings_provider_test.dart`
Expected: FAIL — compile error: `The getter 'terminalType' isn't defined for the class 'SettingsProvider'`.

- [ ] **Step 3: Implement in `SettingsProvider`**

In `app/lib/providers/settings_provider.dart`:

(a) Field — after `String terminalFont = 'MesloLGS NF';` (line 17):

```dart
  String terminalType = 'xterm-256color';
```

(b) `_load()` — after the `terminalFont` line (line 46):

```dart
    terminalType = prefs.getString('terminalType') ?? 'xterm-256color';
```

(c) `save()` — add parameter after `String? terminalFont,`:

```dart
    String? terminalType,
```

add assignment after `if (terminalFont != null) this.terminalFont = terminalFont;`:

```dart
    if (terminalType != null) this.terminalType = terminalType;
```

add persist after `await prefs.setString('terminalFont', this.terminalFont);`:

```dart
    await prefs.setString('terminalType', this.terminalType);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/settings_provider_test.dart`
Expected: PASS (all tests, including the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/settings_provider_test.dart
git commit -m "feat(settings): terminalType preference (TERM for SSH sessions)"
```

---

### Task 2: Plumb TERM through SessionProvider → SshService

**Files:**
- Modify: `app/lib/services/ssh_service.dart:368-384`
- Modify: `app/lib/providers/session_provider.dart:24,155`
- Modify: `app/lib/main.dart:172`

No unit-test seam exists here: provider tests construct a real `SshService`, and `openShell` needs a live SSH connection. Verified by `flutter analyze` + the full test suite (and manually in Task 3).

- [ ] **Step 1: Add `termType` parameter to `SshService.openShell`**

In `app/lib/services/ssh_service.dart`, change the signature (line 368):

```dart
  Future<void> openShell(
    SshSession session, {
    bool useTmux = false,
    String termType = 'xterm-256color',
  }) async {
```

and replace `type: 'xterm-256color',` (line 382) with:

```dart
        type: termType,
```

- [ ] **Step 2: Add callback in `SessionProvider`**

In `app/lib/providers/session_provider.dart`, after `bool Function()? tmuxEnabled;` (line 24):

```dart
  String Function()? terminalType;
```

and change the `openShell` call (line 155) to:

```dart
      await _ssh.openShell(
        session,
        useTmux: tmuxEnabled?.call() ?? false,
        termType: terminalType?.call() ?? 'xterm-256color',
      );
```

- [ ] **Step 3: Wire in `main.dart`**

After `_sessionProvider.tmuxEnabled = () => _settingsProvider.tmuxEnabled;` (line 172):

```dart
    _sessionProvider.terminalType = () => _settingsProvider.terminalType;
```

- [ ] **Step 4: Verify**

Run: `cd app && flutter analyze`
Expected: No issues found.

Run: `cd app && flutter test`
Expected: PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart app/lib/providers/session_provider.dart app/lib/main.dart
git commit -m "feat(ssh): send configurable TERM type in PTY request"
```

---

### Task 3: Settings UI dropdown

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart:102-104`

The enclosing `build` already has `final settings = context.watch<SettingsProvider>()`. The `Terminal` section is currently `children: const [...]` — the new row reads `settings`, so the `const` must move onto the `TerminalAppearanceControls` child.

- [ ] **Step 1: Add the dropdown row**

Replace lines 102-104:

```dart
                _Section(title: 'Terminal', children: const [
                  TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ]),
```

with:

```dart
                _Section(title: 'Terminal', children: [
                  _Row(
                    label: 'Terminal emulation type',
                    subtitle: 'TERM reported to the server — applies to new SSH connections',
                    trailing: _DropDown<String>(
                      value: settings.terminalType,
                      items: const ['xterm-256color', 'xterm', 'linux', 'vt100'],
                      labelOf: (t) => t,
                      onChanged: (v) => context.read<SettingsProvider>().save(terminalType: v),
                    ),
                  ),
                  const TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ]),
```

- [ ] **Step 2: Verify**

Run: `cd app && flutter analyze`
Expected: No issues found.

Run: `cd app && flutter test`
Expected: PASS.

- [ ] **Step 3: Manual smoke test**

Run: `cd app && flutter run -d macos`
- Settings → Terminal shows the "Terminal emulation type" dropdown with the 4 options, default `xterm-256color`.
- Pick `vt100`, connect to a host, run `echo $TERM` → prints `vt100`.
- Already-open sessions keep their original TERM.
- Local terminal: `echo $TERM` → still `xterm-256color`.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat(settings): terminal emulation type dropdown in Settings → Terminal"
```
