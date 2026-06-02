# Connection Health Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a live, latency-driven health dot + tooltip on each SSH session tab, and detect half-open silent drops.

**Architecture:** A dedicated `HealthMonitorService` (ChangeNotifier) keyed by `hostId` periodically pings each connected host's live `SSHClient` via `SshService.measureLatency` (a `Stopwatch` around dartssh2's `client.ping()` with a 5s timeout). The monitor is the *sole* pinger — the client's built-in keepalive is disabled to avoid a shared reply-queue race. The session tab reads health by host id and renders a 4-tier colored dot with a hover tooltip.

**Tech Stack:** Flutter, `provider`, dartssh2 (vendored fork), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-02-connection-health-badge-design.md`

All commands run from `app/`.

---

### Task 1: `SessionHealth` model + tone resolution

**Files:**
- Create: `app/lib/models/session_health.dart`
- Test: `app/test/models/session_health_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/session_health_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/session_health.dart';
import 'package:yourssh/models/ssh_session.dart';

void main() {
  group('SessionHealth.fromLatency', () {
    test('maps latency to status by threshold', () {
      expect(SessionHealth.fromLatency(0).status, HealthStatus.healthy);
      expect(SessionHealth.fromLatency(149).status, HealthStatus.healthy);
      expect(SessionHealth.fromLatency(150).status, HealthStatus.degraded);
      expect(SessionHealth.fromLatency(500).status, HealthStatus.degraded);
      expect(SessionHealth.fromLatency(501).status, HealthStatus.down);
      expect(SessionHealth.fromLatency(null).status, HealthStatus.down);
    });

    test('keeps the measured latency value', () {
      expect(SessionHealth.fromLatency(42).latencyMs, 42);
      expect(SessionHealth.fromLatency(null).latencyMs, isNull);
    });

    test('offline constant has offline status and no latency', () {
      expect(SessionHealth.offline.status, HealthStatus.offline);
      expect(SessionHealth.offline.latencyMs, isNull);
    });
  });

  group('badgeToneFor', () {
    test('session status takes precedence over health', () {
      const healthy = SessionHealth(status: HealthStatus.healthy);
      expect(badgeToneFor(SessionStatus.connecting, healthy), BadgeTone.connecting);
      expect(badgeToneFor(SessionStatus.disconnected, healthy), BadgeTone.grey);
      expect(badgeToneFor(SessionStatus.error, healthy), BadgeTone.red);
    });

    test('connected maps from health status', () {
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.healthy)), BadgeTone.green);
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.degraded)), BadgeTone.amber);
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.down)), BadgeTone.red);
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.offline)), BadgeTone.grey);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/session_health_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/models/session_health.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/models/session_health.dart
import 'ssh_session.dart';

/// Health tier of a live SSH connection, derived from round-trip ping latency.
enum HealthStatus { healthy, degraded, down, offline }

/// Visual tone for the session-tab health dot. [connecting] is rendered as a
/// pulsing amber dot; the rest are static colors.
enum BadgeTone { green, amber, red, grey, connecting }

/// Immutable health snapshot for one host connection.
class SessionHealth {
  final HealthStatus status;
  final int? latencyMs;
  final DateTime? lastPingAt;

  const SessionHealth({required this.status, this.latencyMs, this.lastPingAt});

  /// No reading yet (or host not connected).
  static const offline = SessionHealth(status: HealthStatus.offline);

  /// Map a measured latency (ms) to a status. `null` means the ping failed or
  /// timed out — treated as [HealthStatus.down] for a connected host.
  factory SessionHealth.fromLatency(int? ms, {DateTime? at}) {
    if (ms == null) {
      return SessionHealth(status: HealthStatus.down, lastPingAt: at);
    }
    final HealthStatus status;
    if (ms < 150) {
      status = HealthStatus.healthy;
    } else if (ms <= 500) {
      status = HealthStatus.degraded;
    } else {
      status = HealthStatus.down;
    }
    return SessionHealth(status: status, latencyMs: ms, lastPingAt: at);
  }
}

/// Resolve the badge tone. [SessionStatus] (lifecycle) takes precedence over
/// [SessionHealth] (ping result); health only matters while connected.
BadgeTone badgeToneFor(SessionStatus status, SessionHealth health) {
  switch (status) {
    case SessionStatus.connecting:
      return BadgeTone.connecting;
    case SessionStatus.disconnected:
      return BadgeTone.grey;
    case SessionStatus.error:
      return BadgeTone.red;
    case SessionStatus.connected:
      switch (health.status) {
        case HealthStatus.healthy:
          return BadgeTone.green;
        case HealthStatus.degraded:
          return BadgeTone.amber;
        case HealthStatus.down:
          return BadgeTone.red;
        case HealthStatus.offline:
          return BadgeTone.grey;
      }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/session_health_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/session_health.dart app/test/models/session_health_test.dart
git commit -m "feat(health): SessionHealth model + tone resolution"
```

---

### Task 2: `SshService.measureLatency` + disable built-in keepalive

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (remove lines 29 + 31-34; change line 158; add methods after `testConnection`)
- Modify: `app/lib/main.dart` (remove line 143)
- Test: `app/test/services/ssh_service_measure_latency_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/services/ssh_service_measure_latency_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  test('measureLatency returns null for an unknown host', () async {
    final ssh = SshService(StorageService());
    expect(await ssh.measureLatency('no-such-host'), isNull);
  });

  test('connectedHostIds is empty before any connect', () {
    final ssh = SshService(StorageService());
    expect(ssh.connectedHostIds, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/ssh_service_measure_latency_test.dart`
Expected: FAIL — `The method 'measureLatency' isn't defined` / `connectedHostIds` not defined.

- [ ] **Step 3a: Remove the now-dead built-in keepalive plumbing**

In `app/lib/services/ssh_service.dart`, delete the field at line 29:

```dart
  int Function()? keepAliveSecondsProvider;
```

and delete the helper at lines 31-34:

```dart
  Duration? _resolvedKeepAlive() {
    final secs = keepAliveSecondsProvider?.call() ?? 10;
    return secs == 0 ? null : Duration(seconds: secs);
  }
```

- [ ] **Step 3b: Disable built-in keepalive on the client**

In the same file, change the `keepAliveInterval` argument inside the `SSHClient(...)` constructor (was line 158):

```dart
        // Built-in keepalive is disabled: HealthMonitorService is the sole
        // pinger (it both keeps the connection alive and measures latency),
        // avoiding a race on the shared global-request reply queue.
        keepAliveInterval: null,
```

- [ ] **Step 3c: Add `measureLatency` and `connectedHostIds`**

Add these immediately after the `testConnection` method (after its closing `}`):

```dart
  // ── Health monitoring ─────────────────────────────────

  /// Host ids with a live client. Used by HealthMonitorService to know which
  /// connections to ping.
  Iterable<String> get connectedHostIds => _clients.keys;

  /// Round-trip latency (ms) of a keepalive ping over [hostId]'s live client,
  /// or null when there is no client or the ping fails / times out. The timeout
  /// is what surfaces half-open connections (the channel has not closed yet).
  Future<int?> measureLatency(String hostId) async {
    final client = _clients[hostId];
    if (client == null) return null;
    final sw = Stopwatch()..start();
    try {
      await client.ping().timeout(const Duration(seconds: 5));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 3d: Remove the keepalive wiring in main.dart**

In `app/lib/main.dart`, delete line 143:

```dart
    _ssh.keepAliveSecondsProvider = () => _settingsProvider.keepAliveInterval;
```

(The keep-alive interval setting is re-used by `HealthMonitorService` in Task 5; the `SettingsProvider.keepAliveInterval` field and its settings-screen control stay unchanged.)

- [ ] **Step 4: Run tests + analyzer to verify pass and no dead-code lint**

Run: `flutter test test/services/ssh_service_measure_latency_test.dart && flutter analyze lib/services/ssh_service.dart lib/main.dart`
Expected: tests PASS; analyzer reports `No issues found!` (no `unused_element` for the removed helper).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart app/lib/main.dart app/test/services/ssh_service_measure_latency_test.dart
git commit -m "feat(health): SshService.measureLatency; monitor becomes sole pinger"
```

---

### Task 3: `HealthMonitorService`

**Files:**
- Create: `app/lib/services/health_monitor_service.dart`
- Test: `app/test/services/health_monitor_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/services/health_monitor_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/session_health.dart';
import 'package:yourssh/services/health_monitor_service.dart';

void main() {
  group('HealthMonitorService.tick', () {
    test('maps measured latency per host to a status', () async {
      final latencies = <String, int?>{'a': 50, 'b': 300, 'c': 700, 'd': null};
      final monitor = HealthMonitorService(
        measure: (id) async => latencies[id],
        connectedHostIds: () => latencies.keys,
        pollSeconds: () => 10,
      );

      await monitor.tick();

      expect(monitor.healthFor('a').status, HealthStatus.healthy);
      expect(monitor.healthFor('b').status, HealthStatus.degraded);
      expect(monitor.healthFor('c').status, HealthStatus.down);
      expect(monitor.healthFor('d').status, HealthStatus.down);
    });

    test('unknown host is offline', () {
      final monitor = HealthMonitorService(
        measure: (id) async => 10,
        connectedHostIds: () => const <String>[],
        pollSeconds: () => 10,
      );
      expect(monitor.healthFor('ghost').status, HealthStatus.offline);
    });

    test('drops health for hosts no longer connected', () async {
      var ids = <String>['a'];
      final monitor = HealthMonitorService(
        measure: (id) async => 10,
        connectedHostIds: () => ids,
        pollSeconds: () => 10,
      );
      await monitor.tick();
      expect(monitor.healthFor('a').status, HealthStatus.healthy);

      ids = <String>[];
      await monitor.tick();
      expect(monitor.healthFor('a').status, HealthStatus.offline);
    });

    test('notifies listeners on each tick', () async {
      var notes = 0;
      final monitor = HealthMonitorService(
        measure: (id) async => 10,
        connectedHostIds: () => const ['a'],
        pollSeconds: () => 10,
      )..addListener(() => notes++);
      await monitor.tick();
      expect(notes, greaterThan(0));
    });

    test('does not re-probe a host whose previous probe is in flight', () async {
      var calls = 0;
      final gate = Completer<void>();
      final monitor = HealthMonitorService(
        measure: (id) async {
          calls++;
          await gate.future; // never completes during the test
          return 10;
        },
        connectedHostIds: () => const ['a'],
        pollSeconds: () => 10,
      );
      // Start two overlapping ticks without awaiting the first.
      final first = monitor.tick();
      await monitor.tick();
      expect(calls, 1);
      gate.complete();
      await first;
    });
  });
}
```

Add the import at the top of the test file:

```dart
import 'dart:async';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/health_monitor_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/services/health_monitor_service.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// app/lib/services/health_monitor_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/session_health.dart';

/// Periodically pings every connected host and exposes a [SessionHealth] per
/// host id. The single pinger for live connections (built-in keepalive is
/// disabled in SshService), so each probe doubles as a keepalive.
class HealthMonitorService extends ChangeNotifier {
  final Future<int?> Function(String hostId) measure;
  final Iterable<String> Function() connectedHostIds;
  final int Function() pollSeconds;

  final Map<String, SessionHealth> _health = {};
  final Set<String> _inFlight = {};
  Timer? _timer;
  bool _disposed = false;

  HealthMonitorService({
    required this.measure,
    required this.connectedHostIds,
    required this.pollSeconds,
  });

  /// Current health for [hostId], or [SessionHealth.offline] if unmonitored.
  SessionHealth healthFor(String hostId) =>
      _health[hostId] ?? SessionHealth.offline;

  /// Begin periodic probing. Interval comes from [pollSeconds]; a disabled
  /// (<= 0) setting falls back to 15s so the badge still works.
  void start() {
    if (_timer != null) return;
    final secs = pollSeconds();
    final interval = Duration(seconds: secs <= 0 ? 15 : secs);
    _timer = Timer.periodic(interval, (_) => tick());
  }

  /// One probe round: drop stale hosts, then ping each connected host that is
  /// not already in flight. Exposed for tests (call directly instead of waiting
  /// for the timer).
  Future<void> tick() async {
    final ids = connectedHostIds().toSet();
    _health.removeWhere((id, _) => !ids.contains(id));

    final toProbe = ids.where((id) => !_inFlight.contains(id)).toList();
    await Future.wait(toProbe.map((id) async {
      _inFlight.add(id);
      try {
        final ms = await measure(id);
        // The host may have disconnected during the probe.
        if (connectedHostIds().contains(id)) {
          _health[id] = SessionHealth.fromLatency(ms, at: DateTime.now());
        }
      } finally {
        _inFlight.remove(id);
      }
    }));

    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/health_monitor_service_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/health_monitor_service.dart app/test/services/health_monitor_service_test.dart
git commit -m "feat(health): HealthMonitorService with injectable probe"
```

---

### Task 4: `reconnectCount` on `SshSession`

**Files:**
- Modify: `app/lib/models/ssh_session.dart` (add field after `isPinned`, line 19)
- Modify: `app/lib/providers/session_provider.dart` (`_scheduleReconnect`, ~line 149)
- Test: `app/test/models/ssh_session_test.dart` (add a test)

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` of `app/test/models/ssh_session_test.dart`:

```dart
  test('reconnectCount defaults to 0 and is mutable', () {
    final session = SshSession(
      host: Host(id: 'h1', label: 'h1', host: 'example.com', port: 22, username: 'root'),
    );
    expect(session.reconnectCount, 0);
    session.reconnectCount++;
    expect(session.reconnectCount, 1);
  });
```

Ensure these imports exist at the top of the test file (add any that are missing):

```dart
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/ssh_session_test.dart`
Expected: FAIL — `The getter 'reconnectCount' isn't defined for the class 'SshSession'`.

- [ ] **Step 3a: Add the field**

In `app/lib/models/ssh_session.dart`, add the field right after `bool isPinned;` (line 19):

```dart
  /// Number of reconnect attempts scheduled during this session's lifetime.
  /// Shown in the tab health tooltip.
  int reconnectCount = 0;
```

- [ ] **Step 3b: Increment on each scheduled reconnect**

In `app/lib/providers/session_provider.dart`, inside `_scheduleReconnect`, add the increment as the first line of the method body (before `final delay = ...`):

```dart
  void _scheduleReconnect(SshSession session, Host host, {required int attempt}) {
    session.reconnectCount++;
    final delay = (attempt * 2).clamp(2, 60);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/ssh_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/ssh_session.dart app/lib/providers/session_provider.dart app/test/models/ssh_session_test.dart
git commit -m "feat(health): track reconnectCount per session"
```

---

### Task 5: Wire monitor in main.dart + render the badge

**Files:**
- Modify: `app/lib/main.dart` (construct + start + register + dispose the monitor)
- Modify: `app/lib/screens/main_screen.dart` (`_SessionTab`: add health dot + tooltip; add `_HealthDot` widget + helpers)
- Test: `app/test/widgets/health_dot_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/widgets/health_dot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/session_health.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/health_dot.dart';

void main() {
  testWidgets('HealthDot paints the tone color', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HealthDot(tone: BadgeTone.green)),
    ));
    final dot = tester.widget<Container>(find.byKey(const Key('health-dot')));
    final decoration = dot.decoration as BoxDecoration;
    expect(decoration.color, AppColors.accent);
  });

  testWidgets('HealthDot uses red for the red tone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HealthDot(tone: BadgeTone.red)),
    ));
    final dot = tester.widget<Container>(find.byKey(const Key('health-dot')));
    expect((dot.decoration as BoxDecoration).color, AppColors.red);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/health_dot_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/widgets/health_dot.dart'`.

- [ ] **Step 3a: Create the `HealthDot` widget**

Extract the dot into its own widget file so it is testable in isolation and keeps `main_screen.dart` lean.

```dart
// app/lib/widgets/health_dot.dart
import 'package:flutter/material.dart';
import '../models/session_health.dart';
import '../theme/app_theme.dart';

/// 7px connection-health dot. Static color per tone; [BadgeTone.connecting]
/// pulses to signal an in-progress (re)connect.
class HealthDot extends StatefulWidget {
  final BadgeTone tone;
  const HealthDot({super.key, required this.tone});

  @override
  State<HealthDot> createState() => _HealthDotState();
}

class _HealthDotState extends State<HealthDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(HealthDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tone != widget.tone) _syncPulse();
  }

  void _syncPulse() {
    if (widget.tone == BadgeTone.connecting) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _color(BadgeTone tone) {
    switch (tone) {
      case BadgeTone.green:
        return AppColors.accent;
      case BadgeTone.amber:
      case BadgeTone.connecting:
        return AppColors.orange;
      case BadgeTone.red:
        return AppColors.red;
      case BadgeTone.grey:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      key: const Key('health-dot'),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: _color(widget.tone),
        shape: BoxShape.circle,
      ),
    );
    if (widget.tone != BadgeTone.connecting) return dot;
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse),
      child: dot,
    );
  }
}
```

- [ ] **Step 3b: Run the widget test to verify it passes**

Run: `flutter test test/widgets/health_dot_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 3c: Construct, start, register, and dispose the monitor in `main.dart`**

In `app/lib/main.dart`, add the field near the other service/provider fields (e.g., next to `_sessionProvider`):

```dart
  late final HealthMonitorService _healthMonitor;
```

After the `_sessionProvider` is constructed (line 137) and after the line you removed in Task 2, construct and start the monitor:

```dart
    _healthMonitor = HealthMonitorService(
      measure: _ssh.measureLatency,
      connectedHostIds: () => _ssh.connectedHostIds,
      pollSeconds: () => _settingsProvider.keepAliveInterval,
    )..start();
```

Register it in the `MultiProvider` list (alongside the other `ChangeNotifierProvider.value` entries, ~line 285):

```dart
        ChangeNotifierProvider.value(value: _healthMonitor),
```

Dispose it in `dispose()` (near line 266, next to `_sessionProvider.dispose();`):

```dart
    _healthMonitor.dispose();
```

Add the import at the top of `main.dart` (with the other service imports):

```dart
import 'services/health_monitor_service.dart';
```

- [ ] **Step 3d: Render the dot + tooltip in `_SessionTab`**

In `app/lib/screens/main_screen.dart`, add imports at the top (with the other model/widget imports):

```dart
import '../models/session_health.dart';
import '../services/health_monitor_service.dart';
import '../widgets/health_dot.dart';
```

In `_SessionTabState.build`, insert the health dot as the **first** child of the `Row` (before the recording-indicator `Consumer` at line 1309). Watch sessions have no real connection, so skip the dot for them:

```dart
              // Connection health dot (hidden for watch sessions)
              if (!widget.session.isWatch)
                Builder(builder: (context) {
                  final health = context
                      .watch<HealthMonitorService>()
                      .healthFor(widget.session.host.id);
                  final tone = badgeToneFor(widget.session.status, health);
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Tooltip(
                      message: _healthTooltip(widget.session, health),
                      child: HealthDot(tone: tone),
                    ),
                  );
                }),
```

Add these helpers as top-level functions at the bottom of `main_screen.dart` (after the last class):

```dart
String _healthTooltip(SshSession session, SessionHealth health) {
  final latency = health.latencyMs != null ? '${health.latencyMs}ms' : '—';
  final word = switch (health.status) {
    HealthStatus.healthy => 'healthy',
    HealthStatus.degraded => 'degraded',
    HealthStatus.down => 'down',
    HealthStatus.offline => 'connecting…',
  };
  final uptime = _fmtDuration(DateTime.now().difference(session.connectedAt));
  final ping = health.lastPingAt != null
      ? '${DateTime.now().difference(health.lastPingAt!).inSeconds}s ago'
      : '—';
  return '${session.title}\n'
      '$latency · $word\n'
      'Uptime $uptime · last ping $ping\n'
      'Reconnects this session: ${session.reconnectCount}';
}

String _fmtDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
```

- [ ] **Step 4: Verify the full suite + analyzer + a real run**

Run: `flutter test && flutter analyze`
Expected: all tests PASS; analyzer `No issues found!`.

Then a manual smoke check:

Run: `flutter run -d macos`
Expected: connect to a host → a green dot appears at the left of its tab; hovering shows latency / uptime / reconnects; pulling the network (or `sudo pfctl`-blocking the host) flips the dot to red within ~5s; reconnect shows the pulsing amber dot.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart app/lib/screens/main_screen.dart app/lib/widgets/health_dot.dart app/test/widgets/health_dot_test.dart
git commit -m "feat(health): render connection health badge on session tabs"
```

---

### Task 6: Docs (CHANGELOG, roadmap, wiki, version)

Per the repo's PR-to-master convention, update docs before merging.

**Files:**
- Modify: `app/pubspec.yaml` (version bump)
- Modify: `CHANGELOG.md`
- Modify: `docs/roadmap.md`
- Modify: `docs/wiki/` (user guide for the badge + `Home.md` row if applicable)

- [ ] **Step 1: Bump the version**

In `app/pubspec.yaml`, bump `version: 0.1.16+1` → `version: 0.1.17+1`.

- [ ] **Step 2: Update CHANGELOG.md**

Move the current `[Unreleased]` items into a new `## [0.1.17] - 2026-06-02` section, add a fresh empty `[Unreleased]` block, and add under `### Added`:

```markdown
- **Connection health badge** — live latency-driven dot on each session tab (green <150ms / amber 150–500ms / red >500ms or unreachable / grey), with a hover tooltip showing uptime, last-ping age, and reconnect count. Detects half-open silent drops via a 5s keepalive-ping timeout.
```

Update the comparison links at the bottom of the file (add `[0.1.17]`, repoint `[Unreleased]`).

- [ ] **Step 3: Move the roadmap item to Shipped**

In `docs/roadmap.md`, remove **Connection health badge** from the P0 table (row 2) and the "Top 3 suggestions" list, append it to the "Already shipped" paragraph, bump `Current version: 0.1.17`, and set `updated:` to the current date. Renumber the remaining P0 rows.

- [ ] **Step 4: Wiki**

Create/extend a user-guide page describing the badge colors + tooltip (e.g., `docs/wiki/User-Guide-Sessions.md` or the existing sessions/tabs page) and add a row to `docs/wiki/Home.md` if the feature warrants its own entry.

- [ ] **Step 5: Commit**

```bash
git add app/pubspec.yaml CHANGELOG.md docs/roadmap.md docs/wiki
git commit -m "docs: release 0.1.17 — connection health badge"
```

---

## Self-Review

**Spec coverage:**
- Keepalive-ping latency source → Task 2 (`measureLatency` wraps `client.ping()` + 5s timeout). ✓
- 4-tier model + thresholds → Task 1 (`fromLatency`). ✓
- Badge color resolution (SessionStatus precedence) → Task 1 (`badgeToneFor`) + Task 5 (`HealthDot`). ✓
- Tooltip: uptime + latency + last-ping + reconnect count → Task 5 (`_healthTooltip`) + Task 4 (`reconnectCount`). ✓
- `HealthMonitorService` keyed by hostId, single pinger, non-reentrant, drop stale, fallback interval → Task 3. ✓
- Disable built-in keepalive → Task 2 (step 3b). ✓
- Per-host (not per-session) probing — monitor iterates `connectedHostIds` (host ids), tab looks up by `session.host.id` → Tasks 3 + 5. ✓
- Half-open detection via timeout → Task 2. ✓
- Wiring in main.dart → Task 5. ✓
- Non-goals (auto-reconnect on timeout, history graph, other placements, configurable thresholds) — not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `HealthStatus`, `BadgeTone`, `SessionHealth.fromLatency`, `SessionHealth.offline`, `badgeToneFor`, `healthFor`, `measureLatency`, `connectedHostIds`, `reconnectCount`, `HealthDot(tone:)`, `_healthTooltip`, `_fmtDuration` — names used consistently across Tasks 1–5. ✓
