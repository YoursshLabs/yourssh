# Auto-Reconnect & Keepalive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SSH sessions reconnect indefinitely with linear-backoff countdown, and expose the SSH keepalive interval as a user-configurable setting.

**Architecture:** Extend `SettingsProvider` with a `keepAliveInterval` field and change `reconnectAttempts` default to 0 (unlimited). Wire the interval into `SSHClient` via a callback on `SshService`. In `SessionProvider`, replace the attempt-limit check with an unlimited-aware guard, add a countdown timer that overwrites a terminal line each second, and cancel it in `closeSession`/`dispose`.

**Tech Stack:** Flutter/Dart, `dartssh2` (local fork — already has `keepAliveInterval` param), `SharedPreferences`, `xterm` Terminal widget.

---

## File Map

| File | Change |
|---|---|
| `app/lib/providers/settings_provider.dart` | Add `keepAliveInterval int = 10`; change `reconnectAttempts` default to `0`; add to `save()`/`_load()` |
| `app/lib/services/ssh_service.dart` | Add `keepAliveSecondsProvider` callback; add `_resolvedKeepAlive()`; pass to `SSHClient` in `connect()` |
| `app/lib/providers/session_provider.dart` | Unlimited retry logic; `_countdownTimers` map; `_startCountdown()`; cancel in `closeSession`/`dispose` |
| `app/lib/widgets/settings_screen.dart` | Add keep-alive dropdown; add Unlimited to reconnect dropdown |
| `app/lib/main.dart` | Wire `keepAliveSecondsProvider` |
| `app/test/settings_provider_test.dart` | Tests for new fields |
| `app/test/providers/session_provider_test.dart` | Tests for unlimited reconnect + countdown timer cancel |

---

## Task 1: SettingsProvider — add `keepAliveInterval`, change `reconnectAttempts` default

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Test: `app/test/settings_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `app/test/settings_provider_test.dart`:

```dart
  test('keepAliveInterval defaults to 10', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.keepAliveInterval, 10);
  });

  test('save persists keepAliveInterval', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(keepAliveInterval: 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('keepAliveInterval'), 30);
    expect(provider.keepAliveInterval, 30);
  });

  test('loads persisted keepAliveInterval on init', () async {
    SharedPreferences.setMockInitialValues({'keepAliveInterval': 60});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.keepAliveInterval, 60);
  });

  test('reconnectAttempts defaults to 0 (unlimited)', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.reconnectAttempts, 0);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/settings_provider_test.dart
```

Expected: FAIL — `keepAliveInterval` not defined, `reconnectAttempts` default is 3 not 0.

- [ ] **Step 3: Implement changes in `settings_provider.dart`**

Change field declaration (line 9) and add `keepAliveInterval`:
```dart
  bool autoReconnect = true;
  int reconnectAttempts = 0;
  int keepAliveInterval = 10;
```

In `_load()`, after the `reconnectAttempts` line, update default and add new field:
```dart
    reconnectAttempts = prefs.getInt('reconnectAttempts') ?? 0;
    keepAliveInterval = prefs.getInt('keepAliveInterval') ?? 10;
```

Add `keepAliveInterval` param to `save()` signature:
```dart
  Future<void> save({
    bool? autoReconnect,
    int? reconnectAttempts,
    int? keepAliveInterval,
    double? fontSize,
    String? terminalTheme,
    Map<String, String>? hotkeys,
    bool? networkStatsEnabled,
    bool? tmuxEnabled,
    String? terminalFont,
    bool? commandNotificationsEnabled,
    String? recordingPath,
  }) async {
    if (autoReconnect != null) this.autoReconnect = autoReconnect;
    if (reconnectAttempts != null) this.reconnectAttempts = reconnectAttempts;
    if (keepAliveInterval != null) this.keepAliveInterval = keepAliveInterval;
    // ... rest unchanged
    await prefs.setInt('reconnectAttempts', this.reconnectAttempts);
    await prefs.setInt('keepAliveInterval', this.keepAliveInterval);
    // ... rest unchanged
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/settings_provider_test.dart
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/settings_provider_test.dart
git commit -m "feat(settings): add keepAliveInterval; change reconnectAttempts default to 0 (unlimited)"
```

---

## Task 2: SshService — keepalive interval wiring

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1: Add `keepAliveSecondsProvider` and `_resolvedKeepAlive()` to `SshService`**

After the `recordingService` setter (line 27), add:

```dart
  /// Returns the keepalive interval to pass to SSHClient.
  /// Returns null when the user has set the interval to 0 (off).
  int Function()? keepAliveSecondsProvider;

  Duration? _resolvedKeepAlive() {
    final secs = keepAliveSecondsProvider?.call() ?? 10;
    return secs == 0 ? null : Duration(seconds: secs);
  }
```

- [ ] **Step 2: Pass `_resolvedKeepAlive()` to `SSHClient` in `connect()`**

In `connect()`, find the `SSHClient(` constructor call (around line 142). Add `keepAliveInterval`:

```dart
      client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: () => password ?? '',
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        onVerifyHostKey: (type, fp) async {
          if (verifyHostKey != null) return verifyHostKey(type.toString(), fp);
          return true;
        },
        keepAliveInterval: _resolvedKeepAlive(),
      );
```

- [ ] **Step 3: Verify app still analyzes cleanly**

```bash
cd app && flutter analyze lib/services/ssh_service.dart
```

Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat(ssh): wire keepAliveInterval from settings into SSHClient"
```

---

## Task 3: SessionProvider — unlimited reconnect + countdown timer

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Test: `app/test/providers/session_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `app/test/providers/session_provider_test.dart`, inside `group('SessionProvider', ...)`:

```dart
    test('closeSession cancels countdown timer without throwing', () async {
      // Simulate a session being closed while a reconnect countdown is active.
      // We verify no exception is thrown and the session is removed cleanly.
      final host = Host(
        label: 'test',
        host: '127.0.0.1',
        port: 1,
        username: 'x',
      );
      provider.autoReconnectEnabled = () => true;
      provider.reconnectAttempts = () => 0; // unlimited

      final future = provider.connect(host);
      // Give it a tick to create the session.
      await Future<void>.delayed(Duration.zero);

      // Session should exist and be in connecting or error state.
      expect(provider.sessions, isNotEmpty);

      // Close before any timer fires — must not throw.
      provider.closeSession(provider.sessions.first.id);
      expect(provider.sessions, isEmpty);

      await expectLater(future, completes);
    });

    test('unlimited reconnect: session stays connecting after first failure', () async {
      // With unlimited retries, session must NOT go to error after first failure.
      // We check immediately after connect() completes (failure on unreachable host).
      final host = Host(
        label: 'unreachable',
        host: '127.0.0.1',
        port: 1,
        username: 'x',
      );
      provider.autoReconnectEnabled = () => true;
      provider.reconnectAttempts = () => 0; // unlimited

      // connect() returns when _scheduleReconnect is called (doesn't wait for timer).
      final future = provider.connect(host);
      await expectLater(future, completes);

      // Session must be in connecting state (waiting to retry), not error.
      expect(provider.sessions, isNotEmpty);
      expect(provider.sessions.first.status, SessionStatus.connecting);

      // Cleanup.
      provider.closeSession(provider.sessions.first.id);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/providers/session_provider_test.dart
```

Expected: FAIL — `reconnectAttempts` setter doesn't exist yet on `SessionProvider`.

- [ ] **Step 3: Add `reconnectAttempts` setter and `_countdownTimers` to `SessionProvider`**

At the top of `SessionProvider` class, after `_reconnectTimers`, add:

```dart
  final Map<String, Timer> _countdownTimers = {};
```

The `reconnectAttempts` callback already exists as a `Function`. The test assigns it directly — that works because it's a public field. No change needed. The test just needed the right callback type. Remove the setter idea from above — just assign the callback:

```dart
provider.reconnectAttempts = () => 0;
```

This works because `reconnectAttempts` is declared as `int Function()? reconnectAttempts;` which is already assignable.

- [ ] **Step 4: Cancel countdown timers in `dispose()` and `closeSession()`**

In `dispose()`, after the `_reconnectTimers` cancellation block, add:

```dart
    for (final t in _countdownTimers.values) {
      t.cancel();
    }
    _countdownTimers.clear();
```

In `closeSession()`, after `_reconnectTimers.remove(sessionId)?.cancel();`, add:

```dart
    _countdownTimers.remove(sessionId)?.cancel();
```

- [ ] **Step 5: Replace `_scheduleReconnect` with countdown-aware version**

Replace the entire `_scheduleReconnect` method:

```dart
  void _scheduleReconnect(SshSession session, Host host, {required int attempt}) {
    final delay = (attempt * 2).clamp(2, 60);
    session.status = SessionStatus.connecting;
    _safeNotify();

    _startCountdown(session, delay, attempt);

    _reconnectTimers[session.id]?.cancel();
    _reconnectTimers[session.id] = Timer(Duration(seconds: delay), () {
      _reconnectTimers.remove(session.id);
      if (_disposed || !_sessions.contains(session)) return;
      _doConnect(session, host, attempt: attempt);
    });
  }

  void _startCountdown(SshSession session, int totalSeconds, int attempt) {
    _countdownTimers[session.id]?.cancel();
    var remaining = totalSeconds;

    session.terminal.write(
      '\r\n\x1b[33m[Reconnecting in ${remaining}s... (attempt $attempt)]\x1b[0m',
    );

    _countdownTimers[session.id] = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (!_sessions.contains(session)) {
        t.cancel();
        _countdownTimers.remove(session.id);
        return;
      }
      if (remaining <= 0) {
        t.cancel();
        _countdownTimers.remove(session.id);
        session.terminal.write(
          '\r\x1b[2K\x1b[33m[Reconnecting now... (attempt $attempt)]\x1b[0m\r\n',
        );
      } else {
        session.terminal.write(
          '\r\x1b[2K\x1b[33m[Reconnecting in ${remaining}s... (attempt $attempt)]\x1b[0m',
        );
      }
    });
  }
```

- [ ] **Step 6: Update `_doConnect` — unlimited retry logic**

Replace the `catch (e)` block in `_doConnect`:

```dart
    } catch (e) {
      if (!_sessions.contains(session)) return;
      final maxAttempts = reconnectAttempts?.call() ?? 0;
      final isUnlimited = maxAttempts == 0;
      final shouldRetry =
          (autoReconnectEnabled?.call() ?? false) && (isUnlimited || attempt < maxAttempts);
      if (shouldRetry) {
        _scheduleReconnect(session, host, attempt: attempt + 1);
      } else {
        session.status = SessionStatus.error;
        session.errorMessage = attempt > 1
            ? 'Failed after $attempt attempts: $e'
            : e.toString();
        _safeNotify();
      }
    }
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd app && flutter test test/providers/session_provider_test.dart
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_test.dart
git commit -m "feat(session): unlimited reconnect with countdown timer; cancel on close"
```

---

## Task 4: Settings UI — keepalive dropdown + Unlimited option

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

- [ ] **Step 1: Add keepalive interval dropdown after the reconnect attempts row**

Open `app/lib/widgets/settings_screen.dart`. Find the `_Row` for `Max reconnect attempts` (around line 92). Update it and add the keepalive row below it:

```dart
                  _Row(
                    label: 'Max reconnect attempts',
                    trailing: _DropDown<int>(
                      value: settings.reconnectAttempts,
                      items: [0, 1, 3, 5, 10],
                      labelOf: (n) => n == 0 ? 'Unlimited' : '$n times',
                      onChanged: (v) =>
                          context.read<SettingsProvider>().save(reconnectAttempts: v),
                    ),
                  ),
                  _Row(
                    label: 'Keep-alive interval',
                    subtitle: 'How often to ping the server to keep the connection alive',
                    trailing: _DropDown<int>(
                      value: settings.keepAliveInterval,
                      items: [10, 30, 60, 0],
                      labelOf: (n) => n == 0 ? 'Off' : '${n}s',
                      onChanged: (v) =>
                          context.read<SettingsProvider>().save(keepAliveInterval: v),
                    ),
                  ),
```

- [ ] **Step 2: Verify analyze passes**

```bash
cd app && flutter analyze lib/widgets/settings_screen.dart
```

Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat(ui): add keep-alive interval dropdown and Unlimited reconnect option"
```

---

## Task 5: main.dart — wire `keepAliveSecondsProvider`

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Wire `keepAliveSecondsProvider` after the existing reconnect wiring**

Find lines in `main.dart` (around line 130):
```dart
    _sessionProvider.autoReconnectEnabled = () => _settingsProvider.autoReconnect;
    _sessionProvider.reconnectAttempts = () => _settingsProvider.reconnectAttempts;
```

Add immediately after:
```dart
    _sshService.keepAliveSecondsProvider = () => _settingsProvider.keepAliveInterval;
```

- [ ] **Step 2: Run full test suite + analyze**

```bash
cd app && flutter analyze && flutter test
```

Expected: No analyze issues, all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(main): wire keepAliveSecondsProvider to settings"
```

---

## Task 6: Final verification

- [ ] **Step 1: Run full test suite**

```bash
cd app && flutter test
```

Expected: all PASS, no failures.

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze
```

Expected: No issues.

- [ ] **Step 3: Smoke-test manually**

Run the app:
```bash
cd app && flutter run -d macos
```

Check:
1. Settings screen → Connection section has "Keep-alive interval" dropdown (10s / 30s / 60s / Off) and "Max reconnect attempts" shows "Unlimited" as an option.
2. Connect to a real SSH host → watch it stay connected (keepalive pings keep it alive).
3. Kill the SSH server-side (`sudo systemctl stop sshd` or kill the SSH process) → terminal shows countdown "Reconnecting in Xs... (attempt 1)" → reconnects when server comes back.
4. Set reconnect attempts to 3, kill server → after 3 failures, session shows error state.
5. Close a reconnecting tab during countdown — no crash, tab removed cleanly.

- [ ] **Step 4: Final commit if any polish changes made during smoke test**

```bash
git add -p
git commit -m "fix: smoke-test polish for reconnect/keepalive"
```
