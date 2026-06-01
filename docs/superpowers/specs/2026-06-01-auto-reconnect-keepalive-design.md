# Auto-Reconnect & Keepalive — Design Spec

**Date**: 2026-06-01  
**Status**: Approved

## Goal

When an active SSH session drops, the app automatically reconnects indefinitely with a linear-backoff countdown, and sends SSH keepalive pings at a user-configurable interval to detect dead connections early.

---

## Section 1: Data Model & Settings

### `SettingsProvider` — new / changed fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `reconnectAttempts` | `int` | `0` | `0` = unlimited. Previous default was `3`. Existing users are upgraded to unlimited on first launch after update (prefs fall back to new default). |
| `keepAliveInterval` | `int` | `10` | Seconds. `0` = off. |

Both fields persist to `SharedPreferences` via the existing `save()` / `load()` pattern.

### Settings UI — "Connection" section additions

- **Max reconnect attempts** dropdown: `[1, 3, 5, 10, 0→"Unlimited"]` (default: Unlimited)
- **Keep-alive interval** dropdown: `[10→"10s", 30→"30s", 60→"60s", 0→"Off"]` (default: 10s)

---

## Section 2: Reconnect Logic (`SessionProvider`)

### Attempt counter behavior

- Increments across consecutive failures (not reset to 1 on each shell close).
- Resets to 1 when `session.status` is set to `SessionStatus.connected` (successful auth + shell open).
- This causes backoff to slow down progressively when a server is continuously dropping, and restart quickly after a successful connection.

### `SshSession` model change

Add `int reconnectAttempt = 0` field to `SshSession` to track per-session attempt count across reconnect cycles.

### `_doConnect` — unlimited support

```dart
final isUnlimited = maxAttempts == 0;
final shouldRetry = (autoReconnectEnabled?.call() ?? false) &&
    (isUnlimited || attempt < maxAttempts);
```

When `shouldRetry` is true, call `_scheduleReconnect(session, host, attempt: attempt + 1)`.

When the shell closes normally (not an error), always call `_scheduleReconnect(session, host, attempt: 1)` if `autoReconnectEnabled` — same as today, but attempt resets to 1 because a successful connection just completed.

### `_scheduleReconnect` — backoff + countdown

```dart
void _scheduleReconnect(SshSession session, Host host, {required int attempt}) {
  final delay = (attempt * 2).clamp(2, 60); // 2s, 4s, 6s, ... capped at 60s
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
```

### `_startCountdown` — per-second terminal messages

- Uses `Timer.periodic(Duration(seconds: 1), ...)`.
- Each tick overwrites the current line using `\r` to avoid scrolling spam.
- Final message before connect: `[Reconnecting now...]`.
- Stored in `Map<String, Timer> _countdownTimers`.
- Cancelled in `closeSession()` alongside `_reconnectTimers`.

Terminal message format (ANSI yellow):
```
\r\x1b[33m[Reconnecting in Xs... (attempt N)]\x1b[0m
```

---

## Section 3: Keepalive Wiring (`SshService`)

### New callback on `SshService`

```dart
Duration? Function()? keepAliveIntervalProvider;
```

### `connect()` passes interval to `SSHClient`

```dart
keepAliveInterval: _resolvedKeepAlive(),
```

```dart
Duration? _resolvedKeepAlive() {
  final secs = keepAliveIntervalProvider?.call()?.inSeconds ?? 10;
  return secs == 0 ? null : Duration(seconds: secs);
}
```

`null` disables the built-in `SSHKeepAlive` timer inside `dartssh2`.

### `main.dart` wiring

```dart
_sshService.keepAliveIntervalProvider =
    () => Duration(seconds: _settingsProvider.keepAliveInterval);
```

No changes to `dartssh2` — the library handles ping dispatch and will close the transport on failure, which triggers the normal `onDone` → reconnect flow.

---

## Section 4: Edge Cases & Error Handling

| Scenario | Behavior |
|---|---|
| User closes tab during countdown | `closeSession()` cancels both `_reconnectTimers[id]` and `_countdownTimers[id]`; session removed cleanly. |
| `autoReconnect = false` | No retry; session → `SessionStatus.disconnected` immediately. Unchanged. |
| `reconnectAttempts = 1` | Retry once, then stop. Unchanged behavior. |
| Jump host reconnect | `_doConnect` → `connect()` → `_ensureJumpClient()` re-establishes jump client automatically. No special handling needed. |
| Keepalive ping timeout | `dartssh2` transport closes → `onDone` fires → existing `_onShellClosed` → `_scheduleReconnect`. No extra code needed. |
| `keepAliveInterval = 0` | `SSHClient` constructed with `keepAliveInterval: null` → no pings sent. |

---

## Files Changed

| File | Change |
|---|---|
| `app/lib/providers/settings_provider.dart` | Add `keepAliveInterval`, change `reconnectAttempts` default to `0` |
| `app/lib/models/ssh_session.dart` | Add `reconnectAttempt` field |
| `app/lib/providers/session_provider.dart` | Unlimited retry logic, countdown timer, attempt counter reset |
| `app/lib/services/ssh_service.dart` | `keepAliveIntervalProvider` callback + `_resolvedKeepAlive()` |
| `app/lib/widgets/settings_screen.dart` | Keep-alive dropdown + Unlimited option in reconnect dropdown |
| `app/lib/main.dart` | Wire `keepAliveIntervalProvider` |

No changes to `dartssh2` or any other package.
