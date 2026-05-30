# Command Finish Notification — Design Spec

**Date:** 2026-05-30
**Feature:** Phase 1-C — Command finish notification

---

## Goal

Show a system notification (when app is not focused) or an in-app toast (when focused) whenever any SSH or local shell session detects a shell prompt in its output — signalling a long-running command has finished.

---

## Section 1: Architecture

### New service: `NotificationService` (singleton)

`app/lib/services/notification_service.dart`

Responsibilities:
- Track window focus state (`_isWindowFocused`, default `true`)
- Detect prompt in terminal data per session (with debounce + cooldown)
- Dispatch: system notification if not focused, toast if focused
- Hold `enabled` flag (synced from `SettingsProvider`)

```dart
class NotificationService {
  static final instance = NotificationService._();
  NotificationService._();

  bool enabled = true;
  bool _isWindowFocused = true;

  // Set by main.dart; called with the session label when prompt detected and focused
  void Function(String sessionLabel)? onToast;

  final _promptRegex = RegExp(r'[\$#%❯>]\s*$');
  final _ansiRegex = RegExp(r'\x1B\[[0-9;]*[mGKHFABCDJf]');
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, DateTime> _lastNotified = {};
  static const _debounce = Duration(milliseconds: 500);
  static const _cooldown = Duration(seconds: 5);

  static Future<void> init() async {
    await localNotifier.setup(appName: 'YourSSH');
  }

  void onWindowFocus() => _isWindowFocused = true;
  void onWindowBlur() => _isWindowFocused = false;

  void onTerminalData(String data, {required String sessionId, required String sessionLabel}) {
    if (!enabled) return;
    _debounceTimers[sessionId]?.cancel();
    _debounceTimers[sessionId] = Timer(_debounce, () => _checkPrompt(data, sessionId: sessionId, sessionLabel: sessionLabel));
  }

  void _checkPrompt(String data, {required String sessionId, required String sessionLabel}) {
    final stripped = data.replaceAll(_ansiRegex, '');
    final lines = stripped.trimRight().split('\n');
    final lastLine = lines.lastWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (!_promptRegex.hasMatch(lastLine)) return;

    final now = DateTime.now();
    final last = _lastNotified[sessionId];
    if (last != null && now.difference(last) < _cooldown) return;
    _lastNotified[sessionId] = now;

    if (_isWindowFocused) {
      onToast?.call(sessionLabel);
    } else {
      LocalNotification(title: 'YourSSH — Command finished', body: sessionLabel).show();
    }
  }

  void removeSession(String sessionId) {
    _debounceTimers[sessionId]?.cancel();
    _debounceTimers.remove(sessionId);
    _lastNotified.remove(sessionId);
  }
}
```

### Prompt detection heuristic

Strip ANSI escape codes, take the last non-empty line, match against `RegExp(r'[\$#%❯>]\s*$')`. Covers bash (`$ `), zsh (`% `, `❯ `), sh/dash (`$ `), root (`# `), PowerShell (`> `).

**Debounce:** 500ms timer reset on each data chunk — avoids false triggers from streaming output that contains prompt-like characters mid-stream.

**Cooldown:** 5s per session between notifications — avoids spam from scripts that print many prompts.

### Window focus tracking

`_YourSSHAppState` in `main.dart` already mixes in `WindowListener`. Add `onWindowBlur()`:
```dart
@override
void onWindowFocus() {
  NotificationService.instance.onWindowFocus();
  // existing sync pull logic...
}

@override
void onWindowBlur() {
  NotificationService.instance.onWindowBlur();
}
```

### Toast delivery

Add a `GlobalKey<ScaffoldMessengerState>` to `main.dart`, pass to `MaterialApp.scaffoldMessengerKey`. Set `NotificationService.instance.onToast` to show a SnackBar:

```dart
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

// in initState:
NotificationService.instance.onToast = (label) {
  _messengerKey.currentState?.showSnackBar(SnackBar(
    content: Text('✓ $label — command finished'),
    duration: const Duration(seconds: 3),
  ));
};
```

---

## Section 2: Integration points

### SSH sessions (`app/lib/services/ssh_service.dart`)

At line 200 where stdout data is written to terminal:

```dart
// Before:
(data) => session.terminal.write(utf8.convert(data)),

// After:
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

When session is disconnected (`_onShellClosed`), call `NotificationService.instance.removeSession(session.id)`.

### Local shell sessions (`app/lib/services/local_shell_service.dart`)

At line 52 where PTY output is piped to terminal:

```dart
// Before:
.listen(terminal.write);

// After:
.listen((data) {
  terminal.write(data);
  NotificationService.instance.onTerminalData(
    data,
    sessionId: session.id,
    sessionLabel: 'Local Shell',
  );
});
```

When process exits, call `NotificationService.instance.removeSession(session.id)`.

---

## Section 3: Settings

### `SettingsProvider` additions

```dart
bool commandNotificationsEnabled = true;
```

In `_load()`:
```dart
commandNotificationsEnabled = prefs.getBool('commandNotificationsEnabled') ?? true;
```

In `save()` (add param + persist):
```dart
bool? commandNotificationsEnabled,
// ...
if (commandNotificationsEnabled != null) this.commandNotificationsEnabled = commandNotificationsEnabled;
// ...
await prefs.setBool('commandNotificationsEnabled', this.commandNotificationsEnabled);
```

Sync to `NotificationService` from `main.dart` `initState` and whenever settings change:
```dart
// in initState, after providers loaded:
NotificationService.instance.enabled = _settingsProvider.commandNotificationsEnabled;
// listen for changes:
_settingsProvider.addListener(() {
  NotificationService.instance.enabled = _settingsProvider.commandNotificationsEnabled;
});
```

### `settings_screen.dart` addition

Add a `SwitchListTile` in the General section (same pattern as `networkStatsEnabled`):

```dart
SwitchListTile(
  title: const Text('Command finish notification'),
  subtitle: const Text('Alert when a command completes in an unfocused session'),
  value: settings.commandNotificationsEnabled,
  onChanged: (v) => context.read<SettingsProvider>().save(commandNotificationsEnabled: v),
),
```

---

## Section 4: Package

Add to `app/pubspec.yaml` dependencies:
```yaml
local_notifier: ^0.3.0
```

Run `flutter pub get`.

macOS sandbox entitlements: `local_notifier` does not require additional entitlements — it uses `NSUserNotificationCenter` / `UNUserNotificationCenter` which are permitted in the sandbox. No changes to `.entitlements` files needed.

---

## Implementation scope

**Files to create:**
- `app/lib/services/notification_service.dart`

**Files to modify:**
- `app/pubspec.yaml` — add `local_notifier`
- `app/lib/main.dart` — init, `onWindowBlur`, `scaffoldMessengerKey`, `onToast`, settings listener
- `app/lib/services/ssh_service.dart` — intercept stdout data, remove session on close
- `app/lib/services/local_shell_service.dart` — intercept PTY output, remove session on exit
- `app/lib/providers/settings_provider.dart` — add `commandNotificationsEnabled`
- `app/lib/widgets/settings_screen.dart` — add `SwitchListTile`

**Test files:**
- `app/test/services/notification_service_test.dart` — unit tests for prompt detection and cooldown logic
