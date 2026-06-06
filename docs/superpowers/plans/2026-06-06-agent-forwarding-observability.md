# Agent Forwarding Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SSH agent forwarding observable — live agent status in the host panel, a per-session forwarding state icon on the session tab, and a tappable refusal notification — with zero clicks required from the user.

**Architecture:** A pure probe function (`probeAgentStatus`) mirrors `AgentForwardingHandler`'s source order (system agent → Keychain fallback) for pre-connect feedback. At runtime, the handler reports each served request via a callback; `SshService` maps callbacks plus the existing `agentForwardingRefused` flag into `onAgentForwardingEvent`, which `main.dart` wires to `SessionProvider` (per-session `AgentForwardingState`) and `NotificationCenterProvider` (refusal item). UI: `AgentStatusLine` widget in the host panel, key icon on `SessionTab`.

**Tech Stack:** Flutter/Dart, dartssh2 (local fork), provider, flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-06-agent-forwarding-observability-design.md`

**Conventions for this repo:**
- All code/comments/docs in English. Run commands from `app/` (e.g. `cd app && flutter test ...`).
- This codebase uses Dart private named parameters (`this._foo` in a named-param list is called as `foo:`) — `AgentForwardingHandler` already does this; follow suit.
- Commit after every task with a Conventional Commits message.

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/services/agent_probe.dart` | Create | `AgentProbeResult` sealed class + `probeAgentStatus()` (pre-connect probe) |
| `app/lib/models/agent_forwarding_state.dart` | Create | `AgentForwardingState` enum |
| `app/lib/widgets/agent_status_line.dart` | Create | Auto-probing status row widget |
| `app/lib/services/agent_forwarding_handler.dart` | Modify | `onRequestServed` callback |
| `app/lib/models/ssh_session.dart` | Modify | `agentForwardingState` field |
| `app/lib/services/ssh_service.dart` | Modify | `onAgentForwardingEvent`; fire from connect/openShell |
| `app/lib/providers/session_provider.dart` | Modify | `handleAgentForwardingEvent` |
| `app/lib/models/app_notification.dart` | Modify | `AppNotificationType.agentForwarding` |
| `app/lib/widgets/notification_bell.dart` | Modify | Icon + tap-to-jump for agent items |
| `app/lib/main.dart` | Modify | Wire event → provider + notification |
| `app/lib/widgets/session_tab.dart` | Modify | Key icon by state |
| `app/lib/widgets/host_detail_panel.dart` | Modify | Copy, ⓘ tooltip, `AgentStatusLine` placement, `agentProbe` param |

---

### Task 1: `probeAgentStatus()` — pre-connect agent probe

**Files:**
- Create: `app/lib/services/agent_probe.dart`
- Test: `app/test/services/agent_probe_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/services/agent_probe_test.dart`:

```dart
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/agent_forwarding_handler.dart'
    show loadKeyPairsFromFile;
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

void main() {
  late List<SSHKeyPair> onePair;

  setUpAll(() async {
    // Same fixture the agent-forwarding handler tests use.
    onePair = await loadKeyPairsFromFile('test/fixtures/keys/id_ed25519', null);
  });

  test('system agent reachable maps to AgentProbeSystem with identity count',
      () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async => [...onePair, ...onePair],
      loadKeychainIdentities: () async => onePair,
    );
    expect(result, isA<AgentProbeSystem>());
    expect((result as AgentProbeSystem).identityCount, 2);
  });

  test('agent unavailable maps to Keychain fallback with key count', () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async =>
          throw const SSHAgentUnavailableException('none'),
      loadKeychainIdentities: () async => onePair,
    );
    expect(result, isA<AgentProbeKeychain>());
    expect((result as AgentProbeKeychain).keyCount, 1);
  });

  test('agent unavailable and zero Keychain keys maps to AgentProbeNothing',
      () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async =>
          throw const SSHAgentUnavailableException('none'),
      loadKeychainIdentities: () async => const <SSHKeyPair>[],
    );
    expect(result, isA<AgentProbeNothing>());
    expect((result as AgentProbeNothing).detail, isNull);
  });

  test('a throwing Keychain loader maps to AgentProbeNothing, never throws',
      () async {
    final result = await probeAgentStatus(
      listAgentIdentities: () async =>
          throw const SSHAgentUnavailableException('none'),
      loadKeychainIdentities: () async => throw Exception('keychain broken'),
    );
    expect(result, isA<AgentProbeNothing>());
  });

  test('agent failure after connect maps to AgentProbeNothing with detail '
      'and does not consult the Keychain', () async {
    var keychainCalls = 0;
    final result = await probeAgentStatus(
      listAgentIdentities: () async => throw Exception('malformed reply'),
      loadKeychainIdentities: () async {
        keychainCalls++;
        return onePair;
      },
    );
    expect(result, isA<AgentProbeNothing>());
    expect((result as AgentProbeNothing).detail, contains('malformed reply'));
    expect(keychainCalls, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/agent_probe_test.dart`
Expected: FAIL — `agent_probe.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/services/agent_probe.dart`:

```dart
import 'package:dartssh2/dartssh2.dart';

import 'system_agent_proxy.dart';

/// Outcome of a local agent probe — what a forwarded channel would serve
/// right now. Mirrors [AgentForwardingHandler]'s source order: system agent
/// first, app-Keychain keys only when the agent is unreachable.
sealed class AgentProbeResult {
  const AgentProbeResult();
}

/// System agent reachable; it holds [identityCount] identities.
class AgentProbeSystem extends AgentProbeResult {
  const AgentProbeSystem(this.identityCount);
  final int identityCount;
}

/// No system agent; forwarding would serve [keyCount] app-Keychain keys.
class AgentProbeKeychain extends AgentProbeResult {
  const AgentProbeKeychain(this.keyCount);
  final int keyCount;
}

/// Nothing to serve — no agent and no loadable Keychain keys, or the agent
/// failed mid-probe ([detail] carries the error in that case).
class AgentProbeNothing extends AgentProbeResult {
  const AgentProbeNothing([this.detail]);
  final String? detail;
}

/// Connects to the system agent, lists identities, closes. The default
/// identity source for [probeAgentStatus]; split out so tests inject failures.
Future<List<SSHKeyPair>> listSystemAgentIdentities() async {
  final proxy = await SystemAgentProxy.connect();
  try {
    return await proxy.getIdentities();
  } finally {
    // Swallow close errors — same rationale as AgentForwardingHandler.
    await proxy.close().catchError((_) {});
  }
}

/// Pre-connect probe behind the host panel's agent status line. Never
/// throws — every failure maps to a displayable result.
Future<AgentProbeResult> probeAgentStatus({
  Future<List<SSHKeyPair>> Function() listAgentIdentities =
      listSystemAgentIdentities,
  required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
}) async {
  try {
    final identities = await listAgentIdentities();
    return AgentProbeSystem(identities.length);
  } on SSHAgentUnavailableException {
    // Same trigger AgentForwardingHandler uses for its Keychain fallback.
    try {
      final keys = await loadKeychainIdentities();
      return keys.isEmpty
          ? const AgentProbeNothing()
          : AgentProbeKeychain(keys.length);
    } catch (_) {
      return const AgentProbeNothing();
    }
  } catch (e) {
    // Agent reachable but broken (malformed reply, I/O error mid-listing) —
    // runtime forwarding would not fall back here, so neither does the probe.
    return AgentProbeNothing('$e');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/agent_probe_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/agent_probe.dart app/test/services/agent_probe_test.dart
git commit -m "feat(agent): pre-connect agent probe for the status line"
```

---

### Task 2: `AgentForwardingHandler.onRequestServed`

**Files:**
- Modify: `app/lib/services/agent_forwarding_handler.dart`
- Test: `app/test/services/agent_forwarding_handler_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Append inside the existing `group('AgentForwardingHandler', ...)` (after the `'propagates failures that happen after connect succeeded'` test, before the group's closing brace — the group already has the fake-agent `server`/`socketPath` fixtures):

```dart
    test('onRequestServed fires with usedFallback=false on the system-agent '
        'path; a throwing callback does not fail the request', () async {
      final events = <bool>[];
      final handler = AgentForwardingHandler(
        connectSystemAgent: () => SystemAgentProxy.connectTo(socketPath),
        loadKeychainIdentities: () async => const <SSHKeyPair>[],
        onRequestServed: (usedFallback) {
          events.add(usedFallback);
          throw StateError('UI listener blew up');
        },
      );

      final response = await handler.handleRequest(Uint8List.fromList([11]));
      expect(response, equals([12, 0, 0, 0, 0]));
      expect(events, [false]);
    });

    test('onRequestServed fires with usedFallback=true on the Keychain path',
        () async {
      final events = <bool>[];
      final handler = AgentForwardingHandler(
        connectSystemAgent: () async =>
            throw const SSHAgentUnavailableException('none'),
        loadKeychainIdentities: () async => const <SSHKeyPair>[],
        onRequestServed: events.add,
      );

      await handler.handleRequest(Uint8List.fromList([11]));
      expect(events, [true]);
    });

    test('onRequestServed does not fire when the request fails', () async {
      // Agent accepts the connection then dies before replying (same setup as
      // the 'propagates failures' test).
      await server.close();
      server = await ServerSocket.bind(
        InternetAddress('$socketPath.dead2', type: InternetAddressType.unix),
        0,
      );
      addTearDown(() async {
        final f = File('$socketPath.dead2');
        if (await f.exists()) await f.delete();
      });
      server.listen((client) {
        client.destroy();
      });

      final events = <bool>[];
      final handler = AgentForwardingHandler(
        connectSystemAgent: () =>
            SystemAgentProxy.connectTo('$socketPath.dead2'),
        loadKeychainIdentities: () async => const <SSHKeyPair>[],
        onRequestServed: events.add,
      );

      await expectLater(
        handler.handleRequest(Uint8List.fromList([11])),
        throwsA(isA<SSHAgentUnavailableException>()),
      );
      expect(events, isEmpty);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/agent_forwarding_handler_test.dart`
Expected: FAIL — no named parameter `onRequestServed`.

- [ ] **Step 3: Implement the callback**

In `app/lib/services/agent_forwarding_handler.dart`, change the constructor and add the field + notifier:

```dart
  AgentForwardingHandler({
    this._connectSystemAgent = SystemAgentProxy.connect,
    required this._loadKeychainIdentities,
    this.onRequestServed,
  });

  final Future<SystemAgentProxy> Function() _connectSystemAgent;
  final Future<List<SSHKeyPair>> Function() _loadKeychainIdentities;

  /// Fired after each successfully served request — `usedFallback` is true
  /// when the reply came from app-Keychain keys instead of the system agent.
  /// Exceptions are swallowed: observability must never fail the round trip.
  final void Function(bool usedFallback)? onRequestServed;

  void _notifyServed(bool usedFallback) {
    try {
      onRequestServed?.call(usedFallback);
    } catch (_) {}
  }
```

Then in `handleRequest`, capture responses and notify on the two success paths (the fallback branch and the system-agent roundtrip):

```dart
  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    final SystemAgentProxy proxy;
    try {
      proxy = await _connectSystemAgent();
    } on SSHAgentUnavailableException {
      final fallback = await (_fallback ??=
          _loadKeychainIdentities().then(SSHKeyPairAgent.new));
      final response = await fallback.handleRequest(request);
      _notifyServed(true);
      return response;
    }
    try {
      final response = await proxy.roundtrip(request);
      _notifyServed(false);
      return response;
    } on SSHAgentUnavailableException {
      rethrow;
    } catch (e) {
      throw SSHAgentUnavailableException(
          'Agent I/O error after connect: $e');
    } finally {
      // Swallow close errors — a broken-pipe socket throws on close() too,
      // and a finally-block throw would replace the already-wrapped exception.
      await proxy.close().catchError((_) {});
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/agent_forwarding_handler_test.dart`
Expected: PASS (all existing + 3 new tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/agent_forwarding_handler.dart app/test/services/agent_forwarding_handler_test.dart
git commit -m "feat(agent): report served forwarding requests via onRequestServed"
```

---

### Task 3: `AgentForwardingState` enum + `SshSession` field

**Files:**
- Create: `app/lib/models/agent_forwarding_state.dart`
- Modify: `app/lib/models/ssh_session.dart`
- Test: `app/test/providers/session_provider_agent_state_test.dart` (created here, extended in Task 5)

- [ ] **Step 1: Write the failing test**

Create `app/test/providers/session_provider_agent_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

Host _host(String id, {bool forwarding = true}) => Host(
      id: id,
      label: id,
      host: '$id.example.com',
      port: 22,
      username: 'u',
      agentForwarding: forwarding,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('constructor derives ready when the host has forwarding on, off '
      'otherwise', () {
    expect(SshSession(host: _host('a')).agentForwardingState,
        AgentForwardingState.ready);
    expect(SshSession(host: _host('b', forwarding: false)).agentForwardingState,
        AgentForwardingState.off);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/session_provider_agent_state_test.dart`
Expected: FAIL — `agent_forwarding_state.dart` does not exist.

- [ ] **Step 3: Implement enum + field**

Create `app/lib/models/agent_forwarding_state.dart`:

```dart
/// Live agent-forwarding status of one SSH session, surfaced as the key icon
/// on the session tab. `off` hides the icon entirely (host opted out).
enum AgentForwardingState {
  /// Host has agent forwarding disabled.
  off,

  /// Enabled and the shell is open; no agent request served yet.
  ready,

  /// Latest request served via the system agent — proof forwarding works.
  active,

  /// Latest request served from app-Keychain keys (system agent unreachable).
  fallback,

  /// Server refused `auth-agent-req` (AllowAgentForwarding no). Terminal for
  /// the shell — the request is sent once per shell; reset on reconnect.
  refused,
}
```

In `app/lib/models/ssh_session.dart`, add the import and field, and give the constructor a body:

```dart
import 'agent_forwarding_state.dart';
```

After the `reconnectCount` field:

```dart
  /// Live forwarding status shown on the session tab; updated by
  /// SessionProvider.handleAgentForwardingEvent.
  AgentForwardingState agentForwardingState = AgentForwardingState.off;
```

Change the constructor's initializer-list terminator from `;` to a body (fields can't read `host` in the initializer list):

```dart
  })  : id = id ?? const Uuid().v4(),
        terminal = Terminal(maxLines: 10000),
        connectedAt = connectedAt ?? DateTime.now() {
    if (host.agentForwarding) {
      agentForwardingState = AgentForwardingState.ready;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/providers/session_provider_agent_state_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/agent_forwarding_state.dart app/lib/models/ssh_session.dart app/test/providers/session_provider_agent_state_test.dart
git commit -m "feat(agent): per-session AgentForwardingState model"
```

---

### Task 4: `SshService.onAgentForwardingEvent`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`
- Test: `app/test/services/ssh_service_open_shell_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

In `app/test/services/ssh_service_open_shell_test.dart`:

Add imports:

```dart
import 'package:yourssh/models/agent_forwarding_state.dart';
```

Parameterize `_FakeShell` (existing constructions `_FakeShell()` keep compiling):

```dart
class _FakeShell implements SSHSession {
  _FakeShell({this.refused = false});

  final bool refused;
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final resizes = <(int, int)>[];

  @override
  bool get agentForwardingRefused => refused;
  // ... rest unchanged
```

Append three tests at the end of `main()`:

```dart
  test('openShell fires a refused event when the server refuses forwarding',
      () async {
    final svc = SshService(StorageService());
    final host = Host(
        label: 'fake',
        host: 'example.com',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final events = <(String, String?, AgentForwardingState)>[];
    svc.onAgentForwardingEvent =
        (hostId, sessionId, state) => events.add((hostId, sessionId, state));

    final shell = _FakeShell(refused: true);
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(events, [(host.id, session.id, AgentForwardingState.refused)]);

    await shell.close();
    await shellDone;
  });

  test('openShell fires ready when forwarding is enabled and not refused '
      '(resets a stale refused on reconnect)', () async {
    final svc = SshService(StorageService());
    final host = Host(
        label: 'fake',
        host: 'example.com',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final events = <(String, String?, AgentForwardingState)>[];
    svc.onAgentForwardingEvent =
        (hostId, sessionId, state) => events.add((hostId, sessionId, state));

    final shell = _FakeShell();
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(events, [(host.id, session.id, AgentForwardingState.ready)]);

    await shell.close();
    await shellDone;
  });

  test('openShell fires no event when the host has forwarding off', () async {
    final svc = SshService(StorageService());
    final host =
        Host(label: 'fake', host: 'example.com', port: 22, username: 'u');
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final events = <(String, String?, AgentForwardingState)>[];
    svc.onAgentForwardingEvent =
        (hostId, sessionId, state) => events.add((hostId, sessionId, state));

    final shell = _FakeShell();
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(events, isEmpty);

    await shell.close();
    await shellDone;
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: FAIL — `onAgentForwardingEvent` undefined.

- [ ] **Step 3: Implement the event plumbing**

In `app/lib/services/ssh_service.dart`:

Add import:

```dart
import '../models/agent_forwarding_state.dart';
```

Add the callback field right after `keychainIdentitiesLoader` (~line 54):

```dart
  /// Live agent-forwarding events for the session UI (key icon on the tab,
  /// refusal notification). Host-scoped events (sessionId == null) come from
  /// the per-client handler shared by every shell on that host; ready/refused
  /// are per-shell. Wired in main.dart to
  /// SessionProvider.handleAgentForwardingEvent.
  void Function(String hostId, String? sessionId, AgentForwardingState state)?
      onAgentForwardingEvent;
```

In `connect()` (~line 185), extend the handler creation:

```dart
        agentHandler: host.agentForwarding
            ? AgentForwardingHandler(
                loadKeychainIdentities:
                    keychainIdentitiesLoader ?? () async => const <SSHKeyPair>[],
                onRequestServed: (usedFallback) =>
                    onAgentForwardingEvent?.call(
                        host.id,
                        null,
                        usedFallback
                            ? AgentForwardingState.fallback
                            : AgentForwardingState.active),
              )
            : null,
```

In `openShell()` (~line 393), replace the refusal block:

```dart
    // The user opted into agent forwarding for this host, but the server
    // refused it (AllowAgentForwarding no). Match OpenSSH: warn, don't fail.
    if (session.host.agentForwarding) {
      if (shell.agentForwardingRefused) {
        session.terminal
            .write('\r\n\x1b[33m[Agent forwarding refused by server]\x1b[0m\r\n');
        onAgentForwardingEvent?.call(
            session.host.id, session.id, AgentForwardingState.refused);
      } else {
        // Also resets a stale `refused` from a previous shell on reconnect.
        onAgentForwardingEvent?.call(
            session.host.id, session.id, AgentForwardingState.ready);
      }
    }
```

Note: the `onRequestServed` lambda in `connect()` is declarative glue (a ternary mapping) — it is exercised by the handler tests (Task 2) and the provider tests (Task 5); no dedicated connect-path test is added because `connect()` requires a full SSH handshake.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: PASS (3 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_open_shell_test.dart
git commit -m "feat(agent): SshService emits agent-forwarding lifecycle events"
```

---

### Task 5: `SessionProvider.handleAgentForwardingEvent`

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Test: `app/test/providers/session_provider_agent_state_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Extend `app/test/providers/session_provider_agent_state_test.dart`. Add imports:

```dart
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
```

Append a group after the constructor test:

```dart
  group('handleAgentForwardingEvent', () {
    late SessionProvider provider;

    setUp(() {
      provider =
          SessionProvider(SshService(StorageService()), TabMetadataService());
    });

    tearDown(() => provider.dispose());

    SshSession seed(Host host) {
      final s = SshSession(host: host, status: SessionStatus.connected);
      provider.sessions.add(s);
      return s;
    }

    test('host-scoped served event moves every session on that host to active',
        () {
      final s1 = seed(_host('h1'));
      final s2 = seed(_host('h1'));
      final other = seed(_host('h2'));

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);

      expect(s1.agentForwardingState, AgentForwardingState.active);
      expect(s2.agentForwardingState, AgentForwardingState.active);
      expect(other.agentForwardingState, AgentForwardingState.ready);
    });

    test('session-scoped refused only touches that session', () {
      final s1 = seed(_host('h1'));
      final s2 = seed(_host('h1'));

      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.refused);

      expect(s1.agentForwardingState, AgentForwardingState.refused);
      expect(s2.agentForwardingState, AgentForwardingState.ready);
    });

    test('host-scoped event never overrides a per-shell refusal', () {
      final s1 = seed(_host('h1'));
      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.refused);

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);

      expect(s1.agentForwardingState, AgentForwardingState.refused);
    });

    test('session-scoped ready resets refused (reconnect)', () {
      final s1 = seed(_host('h1'));
      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.refused);

      provider.handleAgentForwardingEvent(
          'h1', s1.id, AgentForwardingState.ready);

      expect(s1.agentForwardingState, AgentForwardingState.ready);
    });

    test('event for an unknown session id is a no-op', () {
      seed(_host('h1'));
      expect(
        () => provider.handleAgentForwardingEvent(
            'h1', 'gone', AgentForwardingState.active),
        returnsNormally,
      );
    });

    test('notifies listeners once per effective change, not on no-ops', () {
      final s1 = seed(_host('h1'));
      var notifies = 0;
      provider.addListener(() => notifies++);

      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active);
      provider.handleAgentForwardingEvent(
          'h1', null, AgentForwardingState.active); // same state — no change

      expect(notifies, 1);
      expect(s1.agentForwardingState, AgentForwardingState.active);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/session_provider_agent_state_test.dart`
Expected: FAIL — `handleAgentForwardingEvent` undefined.

- [ ] **Step 3: Implement the handler**

In `app/lib/providers/session_provider.dart`, add the import:

```dart
import '../models/agent_forwarding_state.dart';
```

Add the method (next to the other event-routing methods, e.g. after `setSessionColor`):

```dart
  /// Routes agent-forwarding events from SshService into session state.
  /// sessionId == null targets every session on [hostId] (served requests go
  /// through the client-wide handler); a per-shell `refused` is never
  /// overwritten by host-scoped events — only a per-shell `ready` (reconnect)
  /// resets it.
  void handleAgentForwardingEvent(
      String hostId, String? sessionId, AgentForwardingState state) {
    var changed = false;
    for (final s in sshSessions) {
      final match =
          sessionId != null ? s.id == sessionId : s.host.id == hostId;
      if (!match) continue;
      if (sessionId == null &&
          s.agentForwardingState == AgentForwardingState.refused) {
        continue;
      }
      if (s.agentForwardingState != state) {
        s.agentForwardingState = state;
        changed = true;
      }
    }
    if (changed) _safeNotify();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/providers/session_provider_agent_state_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_agent_state_test.dart
git commit -m "feat(agent): SessionProvider tracks per-session forwarding state"
```

---

### Task 6: Refusal notification (type, bell, main wiring)

**Files:**
- Modify: `app/lib/models/app_notification.dart`
- Modify: `app/lib/widgets/notification_bell.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/widgets/notification_bell_test.dart`, `app/test/providers/notification_center_provider_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `app/test/widgets/notification_bell_test.dart` (uses the existing `pump` helper):

```dart
  testWidgets('agent forwarding item: key_off icon, tap jumps to the session',
      (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(
      type: AppNotificationType.agentForwarding,
      title: 'Agent forwarding refused: u@h',
      dedupeKey: 'agent-refused:s1',
      sessionId: 's1',
    ));
    String? opened;
    await pump(tester, center, onOpenSession: (id) => opened = id);

    await tester.tap(find.byIcon(Icons.notifications_none),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byIcon(Icons.key_off), findsOneWidget);

    await tester.tap(find.text('Agent forwarding refused: u@h'));
    await tester.pump();
    expect(opened, 's1');
    expect(find.text('Notifications'), findsNothing);
  });
```

Append to `app/test/providers/notification_center_provider_test.dart` (match its existing test style):

```dart
  test('agent-refused notifications dedupe per session id', () {
    final p = NotificationCenterProvider();
    p.add(AppNotification(
        type: AppNotificationType.agentForwarding,
        title: 'first',
        dedupeKey: 'agent-refused:s1'));
    p.add(AppNotification(
        type: AppNotificationType.agentForwarding,
        title: 'second',
        dedupeKey: 'agent-refused:s1'));
    expect(p.notifications, hasLength(1));
    expect(p.notifications.single.title, 'second');
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/notification_bell_test.dart test/providers/notification_center_provider_test.dart`
Expected: FAIL — `AppNotificationType.agentForwarding` undefined.

- [ ] **Step 3: Implement**

`app/lib/models/app_notification.dart` — extend the enum and the dedupe doc:

```dart
/// In-app notification types surfaced by the bell in the top tab bar.
enum AppNotificationType { update, sessionDisconnect, agentForwarding }
```

```dart
  /// When set, [add] replaces an existing item with the same key instead of
  /// appending a duplicate (e.g. `update:v0.1.25`, `disconnect:<sessionId>`,
  /// `agent-refused:<sessionId>`).
  final String? dedupeKey;
```

`app/lib/widgets/notification_bell.dart` — in the row widget's `build` (~line 248), replace the `isDisconnect` logic with type switches and widen the tap gate to any item carrying a sessionId:

```dart
  @override
  Widget build(BuildContext context) {
    final icon = switch (item.type) {
      AppNotificationType.sessionDisconnect => Icons.link_off,
      AppNotificationType.agentForwarding => Icons.key_off,
      AppNotificationType.update => Icons.system_update_alt,
    };
    final iconColor = switch (item.type) {
      AppNotificationType.sessionDisconnect ||
      AppNotificationType.agentForwarding =>
        AppColors.orange,
      AppNotificationType.update => AppColors.accent,
    };

    return InkWell(
      onTap: item.sessionId != null
          ? () {
              onClose();
              onOpenSession?.call(item.sessionId!);
            }
          : null,
```

and replace the `Icon(...)` child accordingly:

```dart
            Icon(icon, size: 15, color: iconColor),
```

`app/lib/main.dart` — add the import:

```dart
import 'models/agent_forwarding_state.dart';
```

(adjust the path to match the file's existing model imports, e.g. `package:`-style if that's what main.dart uses), then wire the event right after the `_sessionProvider.onSessionDropped = ...` block (~line 284):

```dart
    _ssh.onAgentForwardingEvent = (hostId, sessionId, state) {
      _sessionProvider.handleAgentForwardingEvent(hostId, sessionId, state);
      if (state == AgentForwardingState.refused && sessionId != null) {
        final session = _sessionProvider.sshSessions
            .where((s) => s.id == sessionId)
            .firstOrNull;
        _notificationCenter.add(AppNotification(
          type: AppNotificationType.agentForwarding,
          title: 'Agent forwarding refused: ${session?.title ?? hostId}',
          body: 'The server refused the agent (AllowAgentForwarding no). '
              'Your local keys are not available on this host.',
          dedupeKey: 'agent-refused:$sessionId',
          sessionId: sessionId,
        ));
      }
    };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/notification_bell_test.dart test/providers/notification_center_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/app_notification.dart app/lib/widgets/notification_bell.dart app/lib/main.dart app/test/widgets/notification_bell_test.dart app/test/providers/notification_center_provider_test.dart
git commit -m "feat(agent): refusal notification with tap-to-jump in the bell"
```

---

### Task 7: `SessionTab` key icon

**Files:**
- Modify: `app/lib/widgets/session_tab.dart`
- Test: `app/test/widgets/session_tab_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

In `app/test/widgets/session_tab_test.dart`, add imports:

```dart
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/theme/app_theme.dart';
```

Append tests (reusing the file's `makeProviders`/`wrap`/`seedSession` helpers):

```dart
  testWidgets('no key icon when the host has forwarding off', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host); // forwarding off by default

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));

    expect(find.byIcon(Icons.key), findsNothing);
  });

  testWidgets('key icon color and tooltip track the forwarding state',
      (tester) async {
    final fwdHost = Host(
        id: 'h9',
        label: 'fwd',
        host: '9.9.9.9',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, fwdHost);
    session.agentForwardingState = AgentForwardingState.refused;

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));

    final icon = tester.widget<Icon>(find.byIcon(Icons.key));
    expect(icon.color, AppColors.red);
    expect(
      find.byTooltip(
          'Agent forwarding refused by server (AllowAgentForwarding no)'),
      findsOneWidget,
    );
  });

  testWidgets('key icon shows accent color when active', (tester) async {
    final fwdHost = Host(
        id: 'h10',
        label: 'fwd2',
        host: '9.9.9.10',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, fwdHost);
    session.agentForwardingState = AgentForwardingState.active;

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));

    expect(tester.widget<Icon>(find.byIcon(Icons.key)).color, AppColors.accent);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/session_tab_test.dart`
Expected: FAIL — no `Icons.key` rendered.

- [ ] **Step 3: Implement the indicator**

In `app/lib/widgets/session_tab.dart`, add the import:

```dart
import '../models/agent_forwarding_state.dart';
```

Insert the icon between the recording indicator `Consumer<RecordingProvider>` block and the color-dot block (~line 290):

```dart
              // Agent-forwarding key icon — only for sessions whose host
              // opted in (state != off), colored by live state.
              if (widget.session case final SshSession ssh
                  when ssh.agentForwardingState != AgentForwardingState.off)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Tooltip(
                    message: agentForwardingTooltip(ssh.agentForwardingState),
                    child: Icon(Icons.key,
                        size: 12,
                        color:
                            agentForwardingColor(ssh.agentForwardingState)),
                  ),
                ),
```

Add the helpers at the bottom of the file (next to `_healthTooltip`; public so tests and a future status bar can reuse them):

```dart
/// Tab key-icon color per live forwarding state (off renders no icon).
Color agentForwardingColor(AgentForwardingState state) => switch (state) {
      AgentForwardingState.ready => const Color(0xFF888888),
      AgentForwardingState.active => AppColors.accent,
      AgentForwardingState.fallback => AppColors.orange,
      AgentForwardingState.refused => AppColors.red,
      AgentForwardingState.off => Colors.transparent,
    };

String agentForwardingTooltip(AgentForwardingState state) => switch (state) {
      AgentForwardingState.ready =>
        'Agent forwarding ready — no key requests from this host yet',
      AgentForwardingState.active =>
        'Agent forwarding active — serving keys from your system agent',
      AgentForwardingState.fallback =>
        'Agent forwarding active — serving app Keychain keys (no system agent found)',
      AgentForwardingState.refused =>
        'Agent forwarding refused by server (AllowAgentForwarding no)',
      AgentForwardingState.off => '',
    };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/session_tab_test.dart`
Expected: PASS (existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/session_tab.dart app/test/widgets/session_tab_test.dart
git commit -m "feat(agent): live forwarding-state key icon on the session tab"
```

---

### Task 8: `AgentStatusLine` widget

**Files:**
- Create: `app/lib/widgets/agent_status_line.dart`
- Test: `app/test/widgets/agent_status_line_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/agent_status_line_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/widgets/agent_status_line.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('probes on mount and renders the system-agent state',
      (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeSystem(3),
    )));
    expect(find.text('Checking SSH agent…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(
        find.text('System agent connected — 3 identities'), findsOneWidget);
  });

  testWidgets('renders the Keychain fallback state', (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeKeychain(1),
    )));
    await tester.pumpAndSettle();
    expect(
      find.text('No system agent — 1 app Keychain key will be offered instead'),
      findsOneWidget,
    );
  });

  testWidgets('renders the nothing-available state with the ssh-add hint',
      (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeNothing(),
    )));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Run "ssh-add <key>" or add a key in Keychain'),
      findsOneWidget,
    );
  });

  testWidgets('renders the agent-error state with detail', (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeNothing('boom'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('SSH agent error: boom'), findsOneWidget);
  });

  testWidgets('refresh re-runs the probe', (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => AgentProbeSystem(++calls),
    )));
    await tester.pumpAndSettle();
    expect(find.text('System agent connected — 1 identity'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('System agent connected — 2 identities'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/agent_status_line_test.dart`
Expected: FAIL — `agent_status_line.dart` does not exist.

- [ ] **Step 3: Implement the widget**

Create `app/lib/widgets/agent_status_line.dart`:

```dart
import 'package:flutter/material.dart';

import '../services/agent_probe.dart';
import '../theme/app_theme.dart';

/// One-line live agent status under the Agent forwarding toggle / SSH Agent
/// auth picker. Probes automatically on mount (zero-click feedback); the
/// refresh icon re-probes after the user changes their agent setup.
class AgentStatusLine extends StatefulWidget {
  const AgentStatusLine({super.key, required this.probe});

  final Future<AgentProbeResult> Function() probe;

  @override
  State<AgentStatusLine> createState() => _AgentStatusLineState();
}

class _AgentStatusLineState extends State<AgentStatusLine> {
  AgentProbeResult? _result; // null = probe in flight

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _result = null);
    final result = await widget.probe();
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (_result) {
      null => (
          Icons.hourglass_empty,
          AppColors.textTertiary,
          'Checking SSH agent…',
        ),
      AgentProbeSystem(:final identityCount) => (
          Icons.check_circle_outline,
          AppColors.accent,
          'System agent connected — $identityCount '
              '${identityCount == 1 ? 'identity' : 'identities'}',
        ),
      AgentProbeKeychain(:final keyCount) => (
          Icons.info_outline,
          AppColors.orange,
          'No system agent — $keyCount app Keychain '
              '${keyCount == 1 ? 'key' : 'keys'} will be offered instead',
        ),
      AgentProbeNothing(:final detail) => (
          Icons.error_outline,
          AppColors.red,
          detail == null
              ? 'No agent and no usable Keychain keys — forwarding will '
                  'offer nothing. Run "ssh-add <key>" or add a key in '
                  'Keychain.'
              : 'SSH agent error: $detail',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 11, height: 1.3)),
          ),
          InkWell(
            onTap: _result == null ? null : _run,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.refresh,
                  size: 13, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/agent_status_line_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/agent_status_line.dart app/test/widgets/agent_status_line_test.dart
git commit -m "feat(agent): auto-probing AgentStatusLine widget"
```

---

### Task 9: Host detail panel — copy, ⓘ tooltip, status line

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart`
- Test: `app/test/widgets/host_detail_panel_agent_forwarding_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

In `app/test/widgets/host_detail_panel_agent_forwarding_test.dart`:

Add imports:

```dart
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/widgets/agent_status_line.dart';
```

Update `pumpPanel` to inject a stub probe (so widget tests never touch a real agent socket):

```dart
  Future<void> pumpPanel(WidgetTester tester,
      {Host? existing,
      Future<AgentProbeResult> Function()? agentProbe}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HostDetailPanel(
              existing: existing,
              agentProbe: agentProbe ?? () async => const AgentProbeSystem(1),
              onClose: () {},
              onSave: (host, _) async => saved = host,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
```

Append tests:

```dart
  testWidgets('status line appears when the toggle is switched on',
      (tester) async {
    await pumpPanel(tester,
        existing: existingHost(),
        agentProbe: () async => const AgentProbeKeychain(2));
    expect(find.byType(AgentStatusLine), findsNothing);

    final toggle = find.widgetWithText(SwitchListTile, 'Agent forwarding');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      find.text(
          'No system agent — 2 app Keychain keys will be offered instead'),
      findsOneWidget,
    );
  });

  testWidgets('only one status line when auth is SSH Agent and forwarding on',
      (tester) async {
    await pumpPanel(tester, existing: existingHost(agentForwarding: true));
    expect(find.byType(AgentStatusLine), findsOneWidget);

    final dropdown = find.byType(DropdownButton<AuthType>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH Agent').last);
    await tester.pumpAndSettle();

    expect(find.byType(AgentStatusLine), findsOneWidget);
  });

  testWidgets('info tooltip explains agent auth vs forwarding',
      (tester) async {
    await pumpPanel(tester, existing: existingHost());
    final tooltip = find.byWidgetPredicate((w) =>
        w is Tooltip &&
        (w.message ?? '').startsWith('SSH Agent auth:'));
    expect(tooltip, findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/host_detail_panel_agent_forwarding_test.dart`
Expected: FAIL — no named parameter `agentProbe`.

- [ ] **Step 3: Implement the panel changes**

In `app/lib/widgets/host_detail_panel.dart`:

Add imports:

```dart
import '../services/agent_probe.dart';
import 'agent_status_line.dart';
```

Add the widget parameter (after `onConnect`):

```dart
  /// Test seam for the agent status line; defaults to the real probe using
  /// SshService's Keychain loader.
  final Future<AgentProbeResult> Function()? agentProbe;
```

and to the constructor: `this.agentProbe,`.

Add a probe resolver in `_HostDetailPanelState` (after `_clearTestResult`):

```dart
  Future<AgentProbeResult> _probeAgent() {
    final custom = widget.agentProbe;
    if (custom != null) return custom();
    final loader = context.read<SshService>().keychainIdentitiesLoader;
    return probeAgentStatus(
        loadKeychainIdentities: loader ?? () async => const []);
  }
```

In the AUTH METHOD `_Card` (~line 273–309), append after the private-key sub-dropdown block:

```dart
                    if (_authType == AuthType.agent) ...[
                      _divider(),
                      AgentStatusLine(
                          key: const ValueKey('auth-agent-status'),
                          probe: _probeAgent),
                    ],
```

Replace the Agent forwarding `SwitchListTile` (~line 450) title/subtitle and add the status line after it (inside the same `_Card` children list):

```dart
                    SwitchListTile(
                      value: _agentForwarding,
                      onChanged: (v) => setState(() => _agentForwarding = v),
                      title: const Row(children: [
                        Text(
                          'Agent forwarding',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                        ),
                        SizedBox(width: 4),
                        Tooltip(
                          message:
                              'SSH Agent auth: your agent\'s keys log you in '
                              'to THIS host.\n'
                              'Agent forwarding: this host can borrow your '
                              'local keys to reach other places (git pull, '
                              'ssh to the next hop). Private keys never '
                              'leave your machine.\n'
                              'Only enable for trusted hosts — root on the '
                              'host can use your keys while you are '
                              'connected.',
                          child: Icon(Icons.info_outline,
                              size: 13, color: AppColors.textTertiary),
                        ),
                      ]),
                      subtitle: const Text(
                        'Let this host use your local SSH keys for onward '
                        'connections — git, ssh to other servers (like '
                        'ssh -A). Applies on next connect.',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
                    // Zero-click feedback: probes on appearance. The auth
                    // section owns the line when auth = SSH Agent (spec: one
                    // probe, no duplicate row).
                    if (_agentForwarding && _authType != AuthType.agent)
                      AgentStatusLine(
                          key: const ValueKey('forwarding-status'),
                          probe: _probeAgent),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/host_detail_panel_agent_forwarding_test.dart`
Expected: PASS (2 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart app/test/widgets/host_detail_panel_agent_forwarding_test.dart
git commit -m "feat(agent): host panel agent status line, clearer copy, hover explainer"
```

---

### Task 10: Docs, changelog, full verification

**Files:**
- Modify: `CHANGELOG.md`, `CLAUDE.md`, `docs/wiki/User-Guide-SSH-Connections.md`

- [ ] **Step 1: Full analyze + test run**

Run: `cd app && flutter analyze && flutter test`
Expected: analyze clean; all tests pass. Fix anything that fails before proceeding.

- [ ] **Step 2: Update CHANGELOG.md**

Read the `[Unreleased]` section and add under `### Added` (create the subsection if missing, matching the file's existing style):

```markdown
- Agent forwarding observability: live SSH agent status in the host panel
  (system agent / Keychain fallback / nothing detected), a per-session key
  icon on the session tab (ready / active / fallback / refused), and a
  notification-bell item with tap-to-jump when the server refuses forwarding.
```

- [ ] **Step 3: Update CLAUDE.md**

In the Services section, extend the `AgentForwardingHandler` bullet with: "fires `onRequestServed(usedFallback)` after each served request (feeds the per-session forwarding state)". Add a bullet for `agent_probe.dart`: "pure pre-connect probe (`probeAgentStatus`) behind the host panel's `AgentStatusLine` — system agent identity count, Keychain-fallback key count, or nothing". In the Providers section, extend `SessionProvider` with: "`handleAgentForwardingEvent` tracks per-session `AgentForwardingState` (ready/active/fallback/refused) shown as a key icon on `SessionTab`; refusal also lands in the notification bell". In Key models, note `AgentForwardingState` enum.

- [ ] **Step 4: Update the user guide**

In `docs/wiki/User-Guide-SSH-Connections.md`, append to the agent forwarding section (~lines 31–46), adapting heading level to the file's style:

```markdown
**How to tell it's working**

- When you switch the toggle on, a status line appears and checks your local
  agent automatically: ✓ "System agent connected — N identities" means
  forwarding will serve your `ssh-agent` keys; ⚠ "No system agent — N app
  Keychain keys will be offered instead" means the app falls back to keys
  stored in its Keychain; ✗ "No agent and no usable Keychain keys" means
  forwarding would offer nothing — run `ssh-add <key>` or add a key in
  Keychain.
- While connected, the session tab shows a small key icon: grey = enabled but
  no key requests yet, green = a request was just served by your system
  agent, yellow = served from app Keychain keys, red = the server refused
  forwarding (`AllowAgentForwarding no`). Hover the icon for details.
- If the server refuses forwarding you also get a notification in the bell;
  clicking it jumps to that session.
```

Also do the spec's error-message audit here: skim `system_agent_proxy.dart` and `ssh_service.dart` agent error strings and confirm each names a concrete next action (`ssh-add`, start the OpenSSH Authentication Agent service, set `SSH_AUTH_SOCK`). They were reviewed as adequate at design time — only edit if one lacks an action.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md CLAUDE.md docs/wiki/User-Guide-SSH-Connections.md
git commit -m "docs: agent forwarding observability (changelog, CLAUDE.md, user guide)"
```

---

## Verification checklist (after all tasks)

- [ ] `cd app && flutter analyze` — clean
- [ ] `cd app && flutter test` — all green
- [ ] Manual smoke (optional, macOS): `cd app && flutter run -d macos` — open a host with forwarding on; check the status line probes by itself, the tab shows a grey key that turns green after `ssh-add -l` on the remote, and a host with `AllowAgentForwarding no` produces the bell notification that jumps to the session.
