# Connection Health Badge — Design

> Status: approved (design) · 2026-06-02
> Roadmap item: P0 #2 "Connection health badge"

## Goal

Show live connection health on each SSH session tab: a small colored dot driven
by measured round-trip latency, plus a hover tooltip with uptime, last ping, and
reconnect count. The badge must also detect **half-open silent drops** (network
gone but the channel not yet closed), which the existing reconnect path cannot
catch on its own.

## Scope decisions (from brainstorming)

- **Latency source:** active keepalive ping over the *live* `SSHClient`, not a
  fresh `testConnection()`. The vendored dartssh2 fork exposes
  `SSHClient.ping()` (`packages/dartssh2/lib/src/ssh_client.dart:670`) which
  sends a `keepalive@openssh.com` global request and awaits the reply — wrapping
  it in a `Stopwatch` yields round-trip latency.
- **State model:** 4-tier by latency (healthy / degraded / down / offline).
- **Tooltip:** uptime (from `connectedAt`) + latency + last-ping age + reconnect
  count. "Last-active" means uptime since connect, not terminal I/O activity
  (no output-stream hooking needed).
- **Architecture:** a dedicated `HealthMonitorService` (Approach A), keyed by
  `hostId`, that is the *single* pinger (built-in keepalive disabled on shell
  clients to avoid a shared reply-queue race).

## Components & files

### New

- `app/lib/models/session_health.dart`
  - `enum HealthStatus { healthy, degraded, down, offline }`
  - Immutable `SessionHealth { HealthStatus status, int? latencyMs, DateTime? lastPingAt }`
    with `const SessionHealth.offline`.
  - `factory SessionHealth.fromLatency(int? ms, {DateTime? at})` mapping latency
    to status (thresholds below).
- `app/lib/services/health_monitor_service.dart`
  - `HealthMonitorService extends ChangeNotifier`.
  - Holds `Map<String, SessionHealth> _health` keyed by **hostId**.
  - Dependencies injected (so it is testable without a real `SSHClient`):
    - `Future<int?> Function(String hostId) measure` — defaults to `SshService.measureLatency`.
    - `Iterable<String> Function() connectedHostIds`.
    - `int Function() pollSeconds` — sourced from the keepalive setting.
  - One periodic `Timer`; each tick pings every connected host once, maps the
    result to `SessionHealth`, updates `_health`, and calls `notifyListeners()`.
  - `SessionHealth healthFor(String hostId)` → current state or `offline`.
  - `start()` / `dispose()` manage the timer.

### Modified

- `app/lib/services/ssh_service.dart`
  - `Future<int?> measureLatency(String hostId)` — `Stopwatch` around
    `_clients[hostId]?.ping().timeout(const Duration(seconds: 5))`; returns ms on
    success, `null` on timeout/error/unknown host.
  - `Iterable<String> get connectedHostIds => _clients.keys`.
  - Shell client construction passes `keepAliveInterval: null` so the monitor is
    the sole pinger (no race on `_globalRequestReplyQueue`).
- `app/lib/models/ssh_session.dart` — add `int reconnectCount = 0;`.
- `app/lib/providers/session_provider.dart` — increment `session.reconnectCount`
  inside `_scheduleReconnect`.
- `app/lib/main.dart` — construct `HealthMonitorService` (inject
  `ssh.measureLatency`, `() => ssh.connectedHostIds`, keepalive-seconds getter),
  `start()` it, register it in the `MultiProvider`.
- `app/lib/screens/main_screen.dart` (`_SessionTab`) — add a 7px health dot at
  the left of the tab (consistent with the existing recording/color dots),
  wrapped in a `Tooltip`.

## Data model & colors

`measureLatency` → `HealthStatus` (only meaningful while `session.status == connected`):

| latency             | status   | color        |
|---------------------|----------|--------------|
| `< 150ms`           | healthy  | green        |
| `150–500ms`         | degraded | amber        |
| `> 500ms` or fail   | down     | red          |
| no reading yet      | offline  | dim grey     |

Boundaries: `<150` healthy, `150..500` degraded inclusive, `>500` down.

### Badge color resolution (UI helper)

`SessionStatus` takes precedence over `SessionHealth`:

- `connecting` (includes reconnecting) → pulsing amber
- `disconnected` → grey
- `error` → red
- `connected` → per `SessionHealth` table above

## Data flow

```
HealthMonitorService timer (interval = keepAlive setting, default 10s; fallback 15s if keepalive disabled)
  └─ for each connectedHostId: ssh.measureLatency(hostId)
        └─ _clients[hostId].ping()   ← keepalive@openssh.com + Stopwatch + timeout(5s)
  └─ SessionHealth.fromLatency(ms) → _health[hostId] → notifyListeners()

_SessionTab build:
  health = context.watch<HealthMonitorService>().healthFor(session.host.id)
  dot color = resolve(session.status, health)
  tooltip = "{title}\n{color} {ms}ms · {statusWord}\nUptime {d} · last ping {n}s ago\nReconnects this session: {session.reconnectCount}"
```

Multiple tabs of the same host share one ping (keyed by hostId) — no duplicate
probes.

## Error handling & edge cases

- **Half-open silent drop:** `ping()` hangs → `timeout(5s)` → `null` → down
  (red). This is the feature's added value over passive status, because the
  channel has not closed so the existing reconnect path is not triggered.
- `measureLatency` for a hostId no longer in `_clients` → `null` → monitor sets
  `offline`.
- On host disconnect (hostId leaves `connectedHostIds`), drop it from `_health`
  / report `offline`.
- **Non-reentrant ticks:** skip a host whose previous probe has not resolved, so
  slow pings do not stack.
- Built-in keepalive is disabled only on the shell client. If the user set
  keepalive seconds to 0, the monitor falls back to a 15s poll so the badge
  still works (the monitor's ping doubles as keepalive).

## Testing

- `SessionHealth.fromLatency`: boundary mapping (149→healthy, 150→degraded,
  500→degraded, 501→down, null→down) and `offline`.
- `HealthMonitorService`: inject a fake `measure` fn returning 50→healthy,
  300→degraded, 700→down, null→down, and a missing host→offline; assert
  `_health` updates and `notifyListeners` fires per tick. No real `SSHClient`
  required because `measure` and `connectedHostIds` are injected.
- (Optional) widget test: badge color for each `SessionStatus` × `SessionHealth`
  combination.

## Non-goals (v1)

- Auto-triggering reconnect on ping timeout (badge only shows red). Deferred to a
  follow-up to avoid reconnect storms and coordination with the existing
  reconnect logic.
- Latency history / sparkline graph.
- Badge anywhere other than the session tab (no host-detail / SFTP placement).
- Per-host configurable thresholds (150/500ms hardcoded in v1).
