# Command Finish Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a system notification (when app is not focused) or an in-app toast (when focused) whenever any SSH or local shell session detects a shell prompt in its output.

**Architecture:** A `NotificationService` singleton intercepts terminal data from `SshService` and `LocalShellService`, strips ANSI codes, detects prompt patterns with per-session debounce (500ms) and cooldown (5s), then dispatches via `local_notifier` (not focused) or `ScaffoldMessenger` toast (focused). A `commandNotificationsEnabled` toggle in `SettingsProvider` lets users opt out.

**Tech Stack:** `local_notifier: ^0.3.0`, `dart:async` (Timer), `flutter_test` (fakeAsync for timer tests).

---

## File Map

| File | Change |
|---|---|
| `app/pubspec.yaml` | Add `local_notifier: ^0.3.0` |
| `app/lib/services/notification_service.dart` | CREATE — singleton service |
| `app/lib/providers/settings_provider.dart` | Add `commandNotificationsEnabled` |
| `app/lib/widgets/settings_screen.dart` | Add `SwitchListTile` toggle |
| `app/lib/main.dart` | Init service, `onWindowBlur`, `scaffoldMessengerKey`, `onToast`, settings listener |
| `app/lib/services/ssh_service.dart` | Intercept stdout data + `removeSession` on disconnect |
| `app/lib/services/local_shell_service.dart` | Intercept PTY output + `removeSession` on exit |
| `app/test/services/notification_service_test.dart` | CREATE — unit tests |

---

## Task 1: Package + SettingsProvider

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/providers/settings_provider.dart`

- [ ] **Step 1: Add `local_notifier` to pubspec**

In `app/pubspec.yaml`, after the `window_manager` line (line 45), add:

```yaml
  # System notifications
  local_notifier: ^0.3.0
```

- [ ] **Step 2: Install the package**

```bash
cd app && flutter pub get
```

Expected: resolves without errors. If version conflict, use `^0.3.1` or check `pub.dev` for latest compatible version.

- [ ] **Step 3: Add `commandNotificationsEnabled` to `SettingsProvider`**

In `app/lib/providers/settings_provider.dart`, add the field after `showSnippets` (line 13):

```dart
  bool showSnippets = false;
  bool commandNotificationsEnabled = true;
```

In `_load()`, after the `showSnippets` line (after `prefs.getBool('showSnippets') ?? false`):

```dart
    showSnippets = prefs.getBool('showSnippets') ?? false;
    commandNotificationsEnabled = prefs.getBool('commandNotificationsEnabled') ?? true;
```

In `save()`, add the parameter after `showSnippets`:

```dart
  Future<void> save({
    bool? autoReconnect,
    int? reconnectAttempts,
    double? fontSize,
    String? terminalTheme,
    Map<String, String>? hotkeys,
    bool? networkStatsEnabled,
    bool? tmuxEnabled,
    String? terminalFont,
    bool? showWebTools,
    bool? showSnippets,
    bool? commandNotificationsEnabled,
  }) async {
```

Inside `save()`, add after the `showSnippets` assignment:

```dart
    if (showSnippets != null) this.showSnippets = showSnippets;
    if (commandNotificationsEnabled != null) this.commandNotificationsEnabled = commandNotificationsEnabled;
```

Inside `save()`, add after the `showSnippets` prefs line:

```dart
    await prefs.setBool('showSnippets', this.showSnippets);
    await prefs.setBool('commandNotificationsEnabled', this.commandNotificationsEnabled);
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test --no-pub
```

Expected: all tests pass (no SettingsProvider tests exist yet, but existing tests must not break).

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/providers/settings_provider.dart
git commit -m "feat: add local_notifier dep and commandNotificationsEnabled setting"
```

---

## Task 2: NotificationService (TDD)

**Files:**
- Create: `app/lib/services/notification_service.dart`
- Create: `app/test/services/notification_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `app/test/services/notification_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/notification_service.dart';

void main() {
  group('NotificationService', () {
    late List<({String title, String body})> systemNotifications;
    late List<String> toasts;
    late NotificationService svc;

    setUp(() {
      systemNotifications = [];
      toasts = [];
      svc = NotificationService.forTest(
        debounce: Duration.zero,
        cooldown: const Duration(seconds: 5),
        onSystemNotify: (title, body) => systemNotifications.add((title: title, body: body)),
      );
      svc.onToast = (label) => toasts.add(label);
    });

    test('detects bash prompt (\$ )', () {
      svc.onWindowBlur();
      svc.onTerminalData('output\nuser@host:~\$ ', sessionId: 's1', sessionLabel: 'prod');
      expect(systemNotifications.length, 1);
      expect(systemNotifications[0].title, 'YourSSH — Command finished');
      expect(systemNotifications[0].body, 'prod');
    });

    test('detects root prompt (# )', () {
      svc.onWindowBlur();
      svc.onTerminalData('output\nroot@host:~# ', sessionId: 's1', sessionLabel: 'server');
      expect(systemNotifications.length, 1);
    });

    test('detects zsh prompt (% )', () {
      svc.onWindowBlur();
      svc.onTerminalData('output\nuser@host % ', sessionId: 's1', sessionLabel: 'mac');
      expect(systemNotifications.length, 1);
    });

    test('detects zsh arrow prompt (❯)', () {
      svc.onWindowBlur();
      svc.onTerminalData('output\n❯ ', sessionId: 's1', sessionLabel: 'zsh');
      expect(systemNotifications.length, 1);
    });

    test('strips ANSI escape codes before matching', () {
      svc.onWindowBlur();
      // prompt with ANSI color codes
      svc.onTerminalData('\x1B[32muser@host\x1B[0m:\x1B[34m~\x1B[0m\$ ', sessionId: 's1', sessionLabel: 'ansi');
      expect(systemNotifications.length, 1);
    });

    test('no match on non-prompt output', () {
      svc.onWindowBlur();
      svc.onTerminalData('Hello world\nSome output line', sessionId: 's1', sessionLabel: 'prod');
      expect(systemNotifications, isEmpty);
    });

    test('uses toast when window is focused', () {
      svc.onWindowFocus();
      svc.onTerminalData('done\nuser@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      expect(toasts, ['prod']);
      expect(systemNotifications, isEmpty);
    });

    test('no notification when enabled=false', () {
      svc.enabled = false;
      svc.onWindowBlur();
      svc.onTerminalData('done\nuser@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      expect(systemNotifications, isEmpty);
      expect(toasts, isEmpty);
    });

    test('cooldown prevents second notification within 5 seconds', () {
      svc.onWindowBlur();
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      expect(systemNotifications.length, 1);
    });

    test('different sessions each get their own notification', () {
      svc.onWindowBlur();
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      svc.onTerminalData('user@host\$ ', sessionId: 's2', sessionLabel: 'staging');
      expect(systemNotifications.length, 2);
    });

    test('removeSession cancels debounce and clears cooldown', () {
      svc.onWindowBlur();
      svc.removeSession('s1');
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      expect(systemNotifications.length, 1);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd app && flutter test test/services/notification_service_test.dart --no-pub
```

Expected: compile error — `NotificationService` not defined.

- [ ] **Step 3: Create `notification_service.dart`**

Create `app/lib/services/notification_service.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  static final instance = NotificationService._();

  NotificationService._()
      : _debounce = const Duration(milliseconds: 500),
        _cooldown = const Duration(seconds: 5),
        _onSystemNotify = null;

  @visibleForTesting
  NotificationService.forTest({
    Duration debounce = Duration.zero,
    Duration cooldown = const Duration(seconds: 5),
    void Function(String title, String body)? onSystemNotify,
  })  : _debounce = debounce,
        _cooldown = cooldown,
        _onSystemNotify = onSystemNotify;

  final Duration _debounce;
  final Duration _cooldown;
  final void Function(String title, String body)? _onSystemNotify;

  bool enabled = true;
  bool _isWindowFocused = true;
  void Function(String sessionLabel)? onToast;

  static final _promptRegex = RegExp(r'[\$#%❯>]\s*$');
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*[mGKHFABCDJf]');

  final Map<String, Timer> _debounceTimers = {};
  final Map<String, DateTime> _lastNotified = {};

  static Future<void> init() async {
    await localNotifier.setup(appName: 'YourSSH');
  }

  void onWindowFocus() => _isWindowFocused = true;
  void onWindowBlur() => _isWindowFocused = false;

  void onTerminalData(
    String data, {
    required String sessionId,
    required String sessionLabel,
  }) {
    if (!enabled) return;
    _debounceTimers[sessionId]?.cancel();
    _debounceTimers[sessionId] = Timer(
      _debounce,
      () => _checkPrompt(data, sessionId: sessionId, sessionLabel: sessionLabel),
    );
  }

  void _checkPrompt(
    String data, {
    required String sessionId,
    required String sessionLabel,
  }) {
    final stripped = data.replaceAll(_ansiRegex, '');
    final lastLine = stripped
        .trimRight()
        .split('\n')
        .lastWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (!_promptRegex.hasMatch(lastLine)) return;

    final now = DateTime.now();
    final last = _lastNotified[sessionId];
    if (last != null && now.difference(last) < _cooldown) return;
    _lastNotified[sessionId] = now;

    if (_isWindowFocused) {
      onToast?.call(sessionLabel);
    } else {
      _dispatchSystem('YourSSH — Command finished', sessionLabel);
    }
  }

  void _dispatchSystem(String title, String body) {
    if (_onSystemNotify != null) {
      _onSystemNotify!(title, body);
    } else {
      LocalNotification(title: title, body: body).show();
    }
  }

  void removeSession(String sessionId) {
    _debounceTimers[sessionId]?.cancel();
    _debounceTimers.remove(sessionId);
    _lastNotified.remove(sessionId);
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/services/notification_service_test.dart --no-pub
```

Expected: all 10 tests pass.

- [ ] **Step 5: Run full suite**

```bash
cd app && flutter test --no-pub
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/notification_service.dart app/test/services/notification_service_test.dart
git commit -m "feat: add NotificationService with prompt detection, debounce, and cooldown"
```

---

## Task 3: Settings UI + wire main.dart

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Add SwitchListTile to settings screen**

In `app/lib/widgets/settings_screen.dart`, in the `'Monitoring'` section (around line 179–189), add after the Network Stats tile and before the closing `]` of that section's `children`:

```dart
                _Section(title: 'Monitoring', children: [
                  SwitchListTile(
                    title: const Text('Network Stats Monitor', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Show Rx/Tx overlay on active session', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.networkStatsEnabled,
                    onChanged: (v) {
                      settings.networkStatsEnabled = v;
                      settings.save();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Command finish notification', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    subtitle: const Text('Alert when a command completes in an unfocused session', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    value: settings.commandNotificationsEnabled,
                    onChanged: (v) => context.read<SettingsProvider>().save(commandNotificationsEnabled: v),
                  ),
                ]),
```

- [ ] **Step 2: Update main.dart — imports + init**

In `app/lib/main.dart`, add the import after the existing services imports:

```dart
import 'services/notification_service.dart';
```

In `main()`, after `await hotKeyManager.unregisterAll();` and before `runApp(...)`, add:

```dart
  await NotificationService.init();
```

So `main()` becomes:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('YourSSH');
  await windowManager.setMinimumSize(const Size(800, 600));
  await hotKeyManager.unregisterAll();
  await NotificationService.init();
  runApp(const YourSSHApp());
}
```

- [ ] **Step 3: Add onWindowBlur + focus wiring**

In `_YourSSHAppState`, update `onWindowFocus` and add `onWindowBlur`:

```dart
  @override
  void onWindowFocus() {
    NotificationService.instance.onWindowFocus();
    if (_syncProvider.enabled) {
      _syncService.pull().then((payload) {
        if (payload != null) {
          _hostProvider.replaceAll(payload.hosts, payload.passwords);
        }
      });
    }
  }

  @override
  void onWindowBlur() {
    NotificationService.instance.onWindowBlur();
  }
```

- [ ] **Step 4: Add scaffoldMessengerKey + onToast + settings listener**

In `_YourSSHAppState`, add the key field after the `late final` declarations (before `initState`):

```dart
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
```

In `initState()`, at the end (after `_syncService.startRetryTimer(...)`), add:

```dart
    NotificationService.instance.enabled = _settingsProvider.commandNotificationsEnabled;
    _settingsProvider.addListener(_syncNotificationSetting);

    NotificationService.instance.onToast = (label) {
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('✓ $label — command finished'),
        duration: const Duration(seconds: 3),
      ));
    };
```

Add the listener method to `_YourSSHAppState`:

```dart
  void _syncNotificationSetting() {
    NotificationService.instance.enabled = _settingsProvider.commandNotificationsEnabled;
  }
```

In `dispose()`, before `super.dispose()`, add:

```dart
    _settingsProvider.removeListener(_syncNotificationSetting);
```

In `build()`, pass `scaffoldMessengerKey` to `MaterialApp`:

```dart
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
      ),
```

- [ ] **Step 5: Run tests**

```bash
cd app && flutter test --no-pub
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/settings_screen.dart app/lib/main.dart
git commit -m "feat: wire NotificationService into main.dart and add settings toggle"
```

---

## Task 4: SSH + local shell integration

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (lines 199–201, 228–231)
- Modify: `app/lib/services/local_shell_service.dart` (lines 50–65, 74–76)

- [ ] **Step 1: Add import to ssh_service.dart**

In `app/lib/services/ssh_service.dart`, add after the existing imports:

```dart
import 'notification_service.dart';
```

- [ ] **Step 2: Intercept SSH stdout**

In `app/lib/services/ssh_service.dart`, find the stdout listener at line 199–200:

```dart
    shell.stdout.cast<List<int>>().listen(
      (data) => session.terminal.write(utf8.convert(data)),
```

Replace the callback with:

```dart
    shell.stdout.cast<List<int>>().listen(
      (data) {
        final text = utf8.convert(data);
        session.terminal.write(text);
        NotificationService.instance.onTerminalData(
          text,
          sessionId: session.id,
          sessionLabel: '${session.host.label} (${session.host.username}@${session.host.host})',
        );
      },
```

- [ ] **Step 3: Remove session on SSH disconnect**

In `app/lib/services/ssh_service.dart`, find `_onShellClosed` at line 228:

```dart
  void _onShellClosed(SshSession session) {
    _shells.remove(session.id);
    session.terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
  }
```

Replace with:

```dart
  void _onShellClosed(SshSession session) {
    _shells.remove(session.id);
    session.terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    NotificationService.instance.removeSession(session.id);
  }
```

- [ ] **Step 4: Add import to local_shell_service.dart**

In `app/lib/services/local_shell_service.dart`, add after the existing imports:

```dart
import 'notification_service.dart';
```

- [ ] **Step 5: Intercept local shell PTY output**

In `app/lib/services/local_shell_service.dart`, find the PTY output listener at lines 50–52:

```dart
      pty.output
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);
```

Replace with:

```dart
      pty.output
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            terminal.write(data);
            NotificationService.instance.onTerminalData(
              data,
              sessionId: session.id,
              sessionLabel: 'Local Shell',
            );
          });
```

- [ ] **Step 6: Remove local session on exit**

In `app/lib/services/local_shell_service.dart`, find the exit handler at lines 62–65:

```dart
      pty.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
      });
```

Replace with:

```dart
      pty.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
        NotificationService.instance.removeSession(session.id);
      });
```

- [ ] **Step 7: Run full test suite**

```bash
cd app && flutter test --no-pub
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/lib/services/ssh_service.dart app/lib/services/local_shell_service.dart
git commit -m "feat: hook SSH and local shell into NotificationService for prompt detection"
```
