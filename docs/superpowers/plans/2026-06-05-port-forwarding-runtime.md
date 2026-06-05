# Port Forwarding Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make saved port-forward rules actually run — start/stop local, remote, and dynamic (SOCKS5) tunnels with auto-reconnect, edit UI, auto-start, and live connection counters.

**Architecture:** A new `PortForwardService` owns all runtime tunnel state (sockets, SSH channels, reconnect loop) behind a small injectable `TunnelTransport` abstraction so tests never need a real SSH server. It acquires clients through a new public `SshService.ensureClient` (reuse-or-auto-connect) and pushes state into `PortForwardProvider` via callbacks wired in `main.dart`. Spec: `docs/superpowers/specs/2026-06-05-port-forwarding-runtime-design.md`.

**Tech Stack:** Flutter/Dart, dartssh2 local fork (`forwardLocal` / `forwardRemote` / `forwardDynamic`), provider, shared_preferences, flutter_test.

---

### Task 1: dartssh2 fork — expose SOCKS connection count

**Files:**
- Modify: `packages/dartssh2/lib/src/ssh_forward.dart` (abstract `SSHDynamicForward`, ~line 31)
- Modify: `packages/dartssh2/lib/src/dynamic_forward_io.dart` (`_SSHDynamicForwardImpl`, ~line 29)

The impl already tracks a private `_connections` set; the interface just needs a getter. (No fork-side test — the fork has no harness for the SOCKS impl; covered via app-side fakes + `flutter analyze`.)

- [ ] **Step 1: Add the getter to the abstract class** in `ssh_forward.dart`, after `bool get isClosed;`:

```dart
  /// Number of currently open SOCKS client connections.
  int get activeConnections;
```

- [ ] **Step 2: Implement it** in `dynamic_forward_io.dart`, inside `_SSHDynamicForwardImpl` after `bool get isClosed => _closed;`:

```dart
  @override
  int get activeConnections => _connections.length;
```

- [ ] **Step 3: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add packages/dartssh2
git commit -m "feat(dartssh2): expose activeConnections on SSHDynamicForward"
```

---

### Task 2: PortForward model — autoStart, activeConnections, new statuses

**Files:**
- Modify: `app/lib/models/port_forward.dart`
- Modify: `app/lib/widgets/port_forwarding_screen.dart:123-127` (keep the exhaustive switch compiling)
- Test: `app/test/models/port_forward_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/port_forward.dart';

void main() {
  test('autoStart round-trips through JSON and defaults to false', () {
    final fwd = PortForward(
      label: 'db',
      type: ForwardType.local,
      localPort: 8080,
      remoteHost: 'db',
      remotePort: 5432,
      autoStart: true,
    );
    final restored = PortForward.fromJson(fwd.toJson());
    expect(restored.autoStart, isTrue);

    final legacy = PortForward.fromJson({
      'id': 'x',
      'label': 'old',
      'type': 'local',
      'localPort': 80,
    });
    expect(legacy.autoStart, isFalse);
  });

  test('status, errorMessage and activeConnections are transient', () {
    final fwd = PortForward(label: 'a', type: ForwardType.dynamic, localPort: 1080)
      ..status = ForwardStatus.active
      ..errorMessage = 'boom'
      ..activeConnections = 3;
    final json = fwd.toJson();
    expect(json.containsKey('status'), isFalse);
    expect(json.containsKey('errorMessage'), isFalse);
    expect(json.containsKey('activeConnections'), isFalse);
    final restored = PortForward.fromJson(json);
    expect(restored.status, ForwardStatus.idle);
    expect(restored.activeConnections, 0);
  });

  test('ForwardStatus has connecting and reconnecting states', () {
    expect(ForwardStatus.values, containsAll([
      ForwardStatus.idle,
      ForwardStatus.connecting,
      ForwardStatus.active,
      ForwardStatus.reconnecting,
      ForwardStatus.error,
    ]));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/port_forward_test.dart`
Expected: FAIL (no `autoStart` / `activeConnections` / `connecting`).

- [ ] **Step 3: Implement the model changes**

In `port_forward.dart`:

```dart
enum ForwardStatus { idle, connecting, active, reconnecting, error }
```

Add fields after `String? errorMessage;`:

```dart
  bool autoStart;

  /// Live piped-connection count while active. Transient, like [status].
  int activeConnections;
```

Constructor — add before the closing `})`:

```dart
    this.autoStart = false,
    this.activeConnections = 0,
```

`toJson` — add `'autoStart': autoStart,` after `'hostId': hostId,`.
`fromJson` — add `autoStart: json['autoStart'] ?? false,` after `hostId: json['hostId'],`.

- [ ] **Step 4: Keep the screen's status switch exhaustive** — in `port_forwarding_screen.dart` replace the `statusColor` switch:

```dart
    final statusColor = switch (fwd.status) {
      ForwardStatus.active => AppColors.accent,
      ForwardStatus.error => AppColors.red,
      ForwardStatus.connecting || ForwardStatus.reconnecting => AppColors.orange,
      ForwardStatus.idle => AppColors.textTertiary,
    };
```

- [ ] **Step 5: Run test + analyze**

Run: `cd app && flutter test test/models/port_forward_test.dart && flutter analyze`
Expected: PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/port_forward.dart app/lib/widgets/port_forwarding_screen.dart app/test/models/port_forward_test.dart
git commit -m "feat(port-forward): autoStart flag, connection counter, connecting/reconnecting statuses"
```

---

### Task 3: PortForwardProvider — update(), setConnections(), ready

**Files:**
- Modify: `app/lib/providers/port_forward_provider.dart`
- Test: `app/test/providers/port_forward_provider_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/port_forward_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  PortForward rule({String label = 'r'}) => PortForward(
      label: label, type: ForwardType.local, localPort: 8080,
      remoteHost: 'db', remotePort: 5432);

  test('update replaces the rule and persists it', () async {
    final p = PortForwardProvider();
    await p.ready;
    final fwd = rule();
    await p.add(fwd);

    final edited = PortForward(
        id: fwd.id, label: 'renamed', type: ForwardType.dynamic,
        localPort: 1080, autoStart: true);
    await p.update(edited);
    expect(p.forwards.single.label, 'renamed');
    expect(p.forwards.single.autoStart, isTrue);

    final p2 = PortForwardProvider();
    await p2.ready;
    expect(p2.forwards.single.label, 'renamed');
    expect(p2.forwards.single.autoStart, isTrue);
  });

  test('update of unknown id is a no-op', () async {
    final p = PortForwardProvider();
    await p.ready;
    await p.update(rule());
    expect(p.forwards, isEmpty);
  });

  test('setConnections updates transient count, drops silently if deleted', () async {
    final p = PortForwardProvider();
    await p.ready;
    final fwd = rule();
    await p.add(fwd);
    p.setConnections(fwd.id, 4);
    expect(p.forwards.single.activeConnections, 4);
    p.setConnections('gone', 9); // must not throw
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/port_forward_provider_test.dart`
Expected: FAIL (no `ready`, `update`, `setConnections`).

- [ ] **Step 3: Implement.** In `port_forward_provider.dart`:

Replace the constructor with:

```dart
  /// Completes when the persisted rules have been loaded (auto-start waits on it).
  late final Future<void> ready;

  PortForwardProvider() {
    ready = _load();
  }
```

Add after `delete`:

```dart
  Future<void> update(PortForward fwd) async {
    final idx = _forwards.indexWhere((f) => f.id == fwd.id);
    if (idx == -1) return;
    _forwards[idx] = fwd;
    await _save();
    notifyListeners();
  }
```

Add after `setStatus`:

```dart
  void setConnections(String id, int connections) {
    final fwd = _forwards.where((f) => f.id == id).firstOrNull;
    if (fwd == null || fwd.activeConnections == connections) return;
    fwd.activeConnections = connections;
    notifyListeners();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/providers/port_forward_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/port_forward_provider.dart app/test/providers/port_forward_provider_test.dart
git commit -m "feat(port-forward): provider update/setConnections + ready future"
```

---

### Task 4: SshService — defaultKeyLookup + public ensureClient

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (`_ensureClient`, ~line 605; field block near `defaultHostKeyVerifier`)
- Test: `app/test/services/ssh_service_connect_test.dart` (extend)

`_ensureClient` today returns a cached client even if its transport is closed, and never resolves the host's key for auto-connect. Fix both and expose it publicly.

- [ ] **Step 1: Write the failing test** — append to `ssh_service_connect_test.dart` (it already mocks SharedPreferences + secure storage in `setUp`):

```dart
  group('ensureClient', () {
    test('throws StateError when not connected and no verifier wired', () async {
      final svc = SshService(StorageService());
      final host = Host(
          label: 'x', host: '127.0.0.1', port: 1, username: 'u');
      expect(() => svc.ensureClient(host), throwsStateError);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/ssh_service_connect_test.dart`
Expected: FAIL — `ensureClient` undefined.

- [ ] **Step 3: Implement.** Next to the `defaultHostKeyVerifier` field declaration add:

```dart
  /// Optional Host.keyId → key entry resolver for auto-connect paths
  /// (exec, tunnels) — mirrors SessionProvider.keyLookup for shells.
  SshKeyEntry? Function(String keyId)? defaultKeyLookup;
```

Replace `_ensureClient` (~line 605) with:

```dart
  /// Returns the open client for [host], reconnecting with stored
  /// credentials when there is none or the cached one is already dead.
  Future<SSHClient> ensureClient(Host host) => _ensureClient(host);

  Future<SSHClient> _ensureClient(Host host) async {
    final existing = _clients[host.id];
    if (existing != null && !existing.isClosed) return existing;
    if (existing != null) _clients.remove(host.id); // dropped link — evict
    final verifier = defaultHostKeyVerifier;
    if (verifier == null) {
      throw StateError(
        'Not connected to ${host.host}. Call connect() first, or wire '
        'SshService.defaultHostKeyVerifier to allow auto-connect.',
      );
    }
    final keyId = host.keyId;
    final keyEntry = keyId == null ? null : defaultKeyLookup?.call(keyId);
    return connect(
      host,
      keyEntry: keyEntry,
      verifyHostKey: (keyType, fp) => verifier(host.host, host.port, keyType, fp),
    );
  }
```

(Keep imports as-is — `SshKeyEntry` is already imported.)

- [ ] **Step 4: Run tests + analyze**

Run: `cd app && flutter test test/services/ssh_service_connect_test.dart && flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_connect_test.dart
git commit -m "feat(ssh): public ensureClient with dead-client eviction and key lookup"
```

---

### Task 5: PortForwardService — transport layer + local forwards + start/stop

**Files:**
- Create: `app/lib/services/port_forward_service.dart`
- Test: `app/test/services/port_forward_service_test.dart` (new)

- [ ] **Step 1: Create the service file** with the transport abstraction and the local-forward runtime:

```dart
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/host.dart';
import '../models/port_forward.dart';

/// Human-readable tunnel failure surfaced to the UI via `onStatus`.
class TunnelException implements Exception {
  final String message;
  const TunnelException(this.message);
  @override
  String toString() => message;
}

/// Minimal transport surface the tunnel runtime needs from an SSH client.
/// Production wraps [SSHClient] ([SshTunnelTransport]); tests use fakes.
abstract class TunnelTransport {
  Future<SSHSocket> openLocal(String remoteHost, int remotePort);
  Future<RemoteListener?> openRemote(int port);
  Future<SSHDynamicForward> openDynamic(String bindHost, int bindPort);
  bool get isClosed;
  Future<void> get done;
}

/// Server-side listener created by a remote-forward request.
abstract class RemoteListener {
  Stream<SSHSocket> get connections;
  void close();
}

class SshTunnelTransport implements TunnelTransport {
  SshTunnelTransport(this._client);
  final SSHClient _client;

  @override
  Future<SSHSocket> openLocal(String remoteHost, int remotePort) =>
      _client.forwardLocal(remoteHost, remotePort);

  @override
  Future<RemoteListener?> openRemote(int port) async {
    final fwd = await _client.forwardRemote(port: port);
    return fwd == null ? null : _SshRemoteListener(fwd);
  }

  @override
  Future<SSHDynamicForward> openDynamic(String bindHost, int bindPort) =>
      _client.forwardDynamic(bindHost: bindHost, bindPort: bindPort);

  @override
  bool get isClosed => _client.isClosed;

  @override
  Future<void> get done => _client.done;
}

class _SshRemoteListener implements RemoteListener {
  _SshRemoteListener(this._forward);
  final SSHRemoteForward _forward;
  @override
  Stream<SSHSocket> get connections => _forward.connections;
  @override
  void close() => _forward.close();
}

/// Runtime engine for port-forward rules. Owns sockets, SSH channels and the
/// reconnect loop; pushes state to PortForwardProvider via the injected
/// callbacks (never imports the provider directly).
class PortForwardService {
  PortForwardService({
    required this.acquireTransport,
    required this.resolveHost,
    required this.onStatus,
    required this.onConnections,
    Future<void> Function(Duration)? delay,
    this.socksSampleInterval = const Duration(seconds: 2),
  }) : _delay = delay ?? ((d) => Future<void>.delayed(d));

  /// SshService.ensureClient wrapped into a transport (wired in main.dart).
  final Future<TunnelTransport> Function(Host host) acquireTransport;
  final Host? Function(String hostId) resolveHost;
  final void Function(String id, ForwardStatus status, {String? error}) onStatus;
  final void Function(String id, int connections) onConnections;
  final Future<void> Function(Duration) _delay;
  final Duration socksSampleInterval;

  final Map<String, _ActiveTunnel> _tunnels = {};
  final Map<String, _HostWatcher> _watchers = {};

  bool isRunning(String forwardId) => _tunnels.containsKey(forwardId);

  /// Bound local port of a running local/dynamic tunnel (tests, diagnostics).
  int? localPortFor(String forwardId) {
    final t = _tunnels[forwardId];
    return t?.localServer?.port ?? t?.socks?.port;
  }

  Future<void> start(PortForward fwd) async {
    if (_tunnels.containsKey(fwd.id)) return;
    final hostId = fwd.hostId;
    if (hostId == null) {
      onStatus(fwd.id, ForwardStatus.error, error: 'Select an SSH host first');
      return;
    }
    final host = resolveHost(hostId);
    if (host == null) {
      onStatus(fwd.id, ForwardStatus.error, error: 'Host not found');
      return;
    }
    final tunnel = _ActiveTunnel(rule: fwd, host: host);
    _tunnels[fwd.id] = tunnel;
    onStatus(fwd.id, ForwardStatus.connecting);
    try {
      final transport = await acquireTransport(host);
      await _open(tunnel, transport);
      _watch(host, transport);
      onStatus(fwd.id, ForwardStatus.active);
    } catch (e) {
      _tunnels.remove(fwd.id);
      await tunnel.dispose();
      onStatus(fwd.id, ForwardStatus.error, error: _describe(e));
    }
  }

  Future<void> stop(String forwardId) async {
    final t = _tunnels.remove(forwardId);
    if (t == null) return;
    t.stopping = true;
    await t.dispose();
    onConnections(forwardId, 0);
    onStatus(forwardId, ForwardStatus.idle);
  }

  Future<void> stopAll() async {
    for (final id in _tunnels.keys.toList()) {
      await stop(id);
    }
  }

  /// Stops every tunnel bound to [hostId] (host deleted).
  Future<void> stopForHost(String hostId) async {
    final ids = _tunnels.values
        .where((t) => t.host.id == hostId)
        .map((t) => t.rule.id)
        .toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  /// Best-effort start of every rule flagged autoStart (app launch).
  /// start() reports failures via onStatus and never throws.
  Future<void> autoStartAll(Iterable<PortForward> rules) async {
    for (final rule in rules.where((r) => r.autoStart).toList()) {
      await start(rule);
    }
  }

  // ── Tunnel opening ─────────────────────────────────────

  Future<void> _open(_ActiveTunnel t, TunnelTransport transport) async {
    t.transport = transport;
    switch (t.rule.type) {
      case ForwardType.local:
        await _bindLocal(t);
      case ForwardType.remote:
        await _openRemote(t);
      case ForwardType.dynamic:
        await _openDynamic(t);
    }
  }

  Future<void> _bindLocal(_ActiveTunnel t) async {
    if (t.localServer != null) return; // still bound from before a drop
    final ServerSocket server;
    try {
      server = await ServerSocket.bind(t.rule.localHost, t.rule.localPort);
    } on SocketException {
      throw TunnelException('Port ${t.rule.localPort} already in use');
    }
    t.localServer = server;
    t.serverSub = server.listen((socket) async {
      try {
        final channel =
            await t.transport.openLocal(t.rule.remoteHost, t.rule.remotePort);
        _pipe(t, socket, channel);
      } catch (_) {
        socket.destroy(); // SSH side unavailable (e.g. mid-reconnect)
      }
    });
  }

  Future<void> _openRemote(_ActiveTunnel t) async {
    final listener = await t.transport.openRemote(t.rule.remotePort);
    if (listener == null) {
      throw const TunnelException('Server refused the remote forward request');
    }
    t.remote = listener;
    t.remoteSub = listener.connections.listen((channel) async {
      try {
        final local =
            await Socket.connect(t.rule.localHost, t.rule.localPort);
        _pipe(t, local, channel);
      } catch (_) {
        channel.destroy(); // local target not reachable
      }
    });
  }

  Future<void> _openDynamic(_ActiveTunnel t) async {
    final SSHDynamicForward socks;
    try {
      socks =
          await t.transport.openDynamic(t.rule.localHost, t.rule.localPort);
    } on SocketException {
      throw TunnelException('Port ${t.rule.localPort} already in use');
    }
    t.socks = socks;
    // The SOCKS server exposes no connection-event stream — sample it.
    t.socksTimer = Timer.periodic(socksSampleInterval, (_) {
      onConnections(t.rule.id, socks.activeConnections);
    });
  }

  /// Bidirectional piping between a local TCP socket and an SSH channel.
  void _pipe(_ActiveTunnel t, Socket local, SSHSocket remote) {
    var finished = false;
    late final void Function() finish;
    finish = () {
      if (finished) return;
      finished = true;
      local.destroy();
      remote.destroy();
      t.closers.remove(finish);
      t.connections--;
      if (!t.stopping) onConnections(t.rule.id, t.connections);
    };
    t.closers.add(finish);
    t.connections++;
    onConnections(t.rule.id, t.connections);
    unawaited(remote.stream
        .cast<List<int>>()
        .pipe(local)
        .catchError((_) {})
        .whenComplete(finish));
    unawaited(local
        .cast<List<int>>()
        .pipe(remote.sink)
        .catchError((_) {})
        .whenComplete(finish));
  }

  // ── Reconnect ──────────────────────────────────────────

  void _watch(Host host, TunnelTransport transport) {
    final existing = _watchers[host.id];
    if (existing != null && identical(existing.transport, transport)) return;
    final watcher = _HostWatcher(host, transport);
    _watchers[host.id] = watcher;
    unawaited(transport.done
        .catchError((_) {})
        .whenComplete(() => _onDropped(watcher)));
  }

  Future<void> _onDropped(_HostWatcher watcher) async {
    if (!identical(_watchers[watcher.host.id], watcher)) return; // superseded
    _watchers.remove(watcher.host.id);
    final affected = _tunnels.values
        .where((t) => t.host.id == watcher.host.id && !t.stopping)
        .toList();
    if (affected.isEmpty) return;
    for (final t in affected) {
      // Local listeners stay bound; only the SSH side is torn down.
      await t.closeSshSide();
      onStatus(t.rule.id, ForwardStatus.reconnecting);
      onConnections(t.rule.id, 0);
    }
    var backoff = const Duration(seconds: 2);
    const cap = Duration(seconds: 30);
    while (true) {
      await _delay(backoff);
      final remaining =
          affected.where((t) => identical(_tunnels[t.rule.id], t)).toList();
      if (remaining.isEmpty) return; // every tunnel stopped while waiting
      final TunnelTransport transport;
      try {
        transport = await acquireTransport(watcher.host);
      } catch (_) {
        backoff = backoff * 2 > cap ? cap : backoff * 2;
        continue;
      }
      for (final t in remaining) {
        if (!identical(_tunnels[t.rule.id], t)) continue; // stopped meanwhile
        try {
          await _open(t, transport);
          onStatus(t.rule.id, ForwardStatus.active);
        } catch (e) {
          _tunnels.remove(t.rule.id);
          await t.dispose();
          onStatus(t.rule.id, ForwardStatus.error, error: _describe(e));
        }
      }
      _watch(watcher.host, transport);
      return;
    }
  }

  String _describe(Object e) {
    if (e is TunnelException) return e.message;
    if (e is SocketException) {
      final os = e.osError?.message;
      return os != null && os.isNotEmpty ? os : e.message;
    }
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }
}

class _ActiveTunnel {
  _ActiveTunnel({required this.rule, required this.host});

  final PortForward rule;
  final Host host;
  late TunnelTransport transport;
  bool stopping = false;

  ServerSocket? localServer;
  StreamSubscription<Socket>? serverSub;
  RemoteListener? remote;
  StreamSubscription<SSHSocket>? remoteSub;
  SSHDynamicForward? socks;
  Timer? socksTimer;

  /// One closer per live piped connection; calling it tears the pair down.
  final Set<void Function()> closers = {};
  int connections = 0;

  /// Tears down everything riding the (dead) SSH connection but keeps the
  /// local listener bound so a reconnect doesn't lose the port.
  Future<void> closeSshSide() async {
    for (final close in closers.toList()) {
      close();
    }
    connections = 0;
    await remoteSub?.cancel();
    remoteSub = null;
    remote?.close();
    remote = null;
    socksTimer?.cancel();
    socksTimer = null;
    await socks?.close();
    socks = null;
  }

  Future<void> dispose() async {
    await closeSshSide();
    await serverSub?.cancel();
    serverSub = null;
    await localServer?.close();
    localServer = null;
  }
}

class _HostWatcher {
  _HostWatcher(this.host, this.transport);
  final Host host;
  final TunnelTransport transport;
}
```

- [ ] **Step 2: Write the test file** with fakes + local-forward and validation tests:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/services/port_forward_service.dart';

// ── Fakes ──────────────────────────────────────────────────

class FakeSshSocket implements SSHSocket {
  final inbound = StreamController<Uint8List>();
  final outbound = <int>[];
  final _sinkController = StreamController<List<int>>();
  final _done = Completer<void>();
  bool destroyed = false;

  FakeSshSocket() {
    _sinkController.stream.listen(outbound.addAll);
  }

  @override
  Stream<Uint8List> get stream => inbound.stream;
  @override
  StreamSink<List<int>> get sink => _sinkController.sink;
  @override
  Future<void> get done => _done.future;
  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }
  @override
  void destroy() {
    destroyed = true;
    if (!inbound.isClosed) inbound.close();
    if (!_done.isCompleted) _done.complete();
  }
}

class FakeRemoteListener implements RemoteListener {
  final controller = StreamController<SSHSocket>();
  bool closed = false;
  @override
  Stream<SSHSocket> get connections => controller.stream;
  @override
  void close() {
    closed = true;
    controller.close();
  }
}

class FakeDynamicForward implements SSHDynamicForward {
  FakeDynamicForward(this.host, this.port);
  @override
  final String host;
  @override
  final int port;
  bool closed = false;
  int connectionCount = 0;
  @override
  bool get isClosed => closed;
  @override
  int get activeConnections => connectionCount;
  @override
  Future<void> close() async => closed = true;
}

class FakeTransport implements TunnelTransport {
  final _done = Completer<void>();
  bool closed = false;
  final opened = <(String, int)>[];
  final sshSockets = <FakeSshSocket>[];
  FakeRemoteListener? remoteListener;
  bool refuseRemote = false;
  FakeDynamicForward? dynamicForward;

  void drop() {
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<SSHSocket> openLocal(String remoteHost, int remotePort) async {
    if (closed) throw const SocketException('connection closed');
    opened.add((remoteHost, remotePort));
    final s = FakeSshSocket();
    sshSockets.add(s);
    return s;
  }

  @override
  Future<RemoteListener?> openRemote(int port) async {
    if (refuseRemote) return null;
    return remoteListener ??= FakeRemoteListener();
  }

  @override
  Future<SSHDynamicForward> openDynamic(String bindHost, int bindPort) async {
    return dynamicForward ??= FakeDynamicForward(bindHost, bindPort);
  }

  @override
  bool get isClosed => closed;
  @override
  Future<void> get done => _done.future;
}

// ── Harness ────────────────────────────────────────────────

void main() {
  final host = Host(
      id: 'h1', label: 'box', host: '10.0.0.1', port: 22, username: 'u');

  PortForward rule({
    ForwardType type = ForwardType.local,
    int localPort = 0,
    String? hostId = 'h1',
  }) =>
      PortForward(
        label: 't',
        type: type,
        localPort: localPort,
        remoteHost: 'db',
        remotePort: 5432,
        hostId: hostId,
      );

  late List<(String, ForwardStatus, String?)> statuses;
  late Map<String, int> conns;
  late List<Duration> delays;
  late List<FakeTransport> transports;
  late int acquireFailures;
  late int acquireCalls;
  late Completer<void>? delayGate;

  PortForwardService makeService() {
    statuses = [];
    conns = {};
    delays = [];
    transports = [FakeTransport()];
    acquireFailures = 0;
    acquireCalls = 0;
    delayGate = null;
    return PortForwardService(
      acquireTransport: (h) async {
        acquireCalls++;
        if (acquireFailures > 0) {
          acquireFailures--;
          throw const SocketException('unreachable');
        }
        return transports.last;
      },
      resolveHost: (id) => id == 'h1' ? host : null,
      onStatus: (id, s, {error}) => statuses.add((id, s, error)),
      onConnections: (id, n) => conns[id] = n,
      delay: (d) async {
        delays.add(d);
        if (delayGate != null) await delayGate!.future;
      },
    );
  }

  ForwardStatus lastStatus(String id) =>
      statuses.lastWhere((s) => s.$1 == id).$2;

  test('start without hostId reports error', () async {
    final svc = makeService();
    final fwd = rule(hostId: null);
    await svc.start(fwd);
    expect(statuses.single.$2, ForwardStatus.error);
    expect(statuses.single.$3, 'Select an SSH host first');
    expect(svc.isRunning(fwd.id), isFalse);
  });

  test('start with unknown host reports error', () async {
    final svc = makeService();
    final fwd = rule(hostId: 'nope');
    await svc.start(fwd);
    expect(lastStatus(fwd.id), ForwardStatus.error);
  });

  test('acquire failure surfaces as error', () async {
    final svc = makeService();
    acquireFailures = 1;
    final fwd = rule();
    await svc.start(fwd);
    expect(
        statuses.map((s) => s.$2),
        [ForwardStatus.connecting, ForwardStatus.error]);
    expect(svc.isRunning(fwd.id), isFalse);
  });

  test('local forward pipes data both ways and counts connections', () async {
    final svc = makeService();
    final fwd = rule();
    await svc.start(fwd);
    expect(lastStatus(fwd.id), ForwardStatus.active);

    final port = svc.localPortFor(fwd.id)!;
    final client = await Socket.connect('127.0.0.1', port);
    client.add([1, 2, 3]);
    await client.flush();
    await pumpEventQueue();

    final channel = transports.last.sshSockets.single;
    expect(transports.last.opened.single, ('db', 5432));
    expect(channel.outbound, [1, 2, 3]);
    expect(conns[fwd.id], 1);

    channel.inbound.add(Uint8List.fromList([9, 8]));
    final received = <int>[];
    final sub = client.listen(received.addAll);
    await pumpEventQueue();
    expect(received, [9, 8]);

    client.destroy();
    await sub.cancel();
    await pumpEventQueue();
    expect(conns[fwd.id], 0);
    await svc.stop(fwd.id);
  });

  test('local port already in use reports friendly error', () async {
    final blocker = await ServerSocket.bind('127.0.0.1', 0);
    final svc = makeService();
    final fwd = rule(localPort: blocker.port);
    await svc.start(fwd);
    expect(lastStatus(fwd.id), ForwardStatus.error);
    expect(statuses.last.$3, 'Port ${blocker.port} already in use');
    await blocker.close();
  });

  test('stop releases the port and reports idle', () async {
    final svc = makeService();
    final fwd = rule();
    await svc.start(fwd);
    final port = svc.localPortFor(fwd.id)!;
    await svc.stop(fwd.id);
    expect(lastStatus(fwd.id), ForwardStatus.idle);
    expect(svc.isRunning(fwd.id), isFalse);
    final rebind = await ServerSocket.bind('127.0.0.1', port);
    await rebind.close();
  });
}
```

- [ ] **Step 3: Run the tests**

Run: `cd app && flutter test test/services/port_forward_service_test.dart`
Expected: PASS (service file was created in Step 1; TDD here is per-behavior — the file is new so tests and code land together).

- [ ] **Step 4: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/port_forward_service.dart app/test/services/port_forward_service_test.dart
git commit -m "feat(port-forward): PortForwardService runtime with local forwards"
```

---

### Task 6: PortForwardService — remote + dynamic tests

The service code from Task 5 already contains `_openRemote` / `_openDynamic`; this task locks the behavior in with tests.

**Files:**
- Test: `app/test/services/port_forward_service_test.dart` (extend)
- Modify (only if a test exposes a bug): `app/lib/services/port_forward_service.dart`

- [ ] **Step 1: Add the remote + dynamic tests** to the existing file:

```dart
  test('remote forward pipes incoming channels to the local target', () async {
    // Local "service" the tunnel should deliver to.
    final echo = await ServerSocket.bind('127.0.0.1', 0);
    final echoData = <int>[];
    echo.listen((s) => s.listen((d) {
          echoData.addAll(d);
          s.add([42]);
        }));

    final svc = makeService();
    final fwd = PortForward(
        label: 'r',
        type: ForwardType.remote,
        localHost: '127.0.0.1',
        localPort: echo.port,
        remotePort: 9000,
        hostId: 'h1');
    await svc.start(fwd);
    expect(lastStatus(fwd.id), ForwardStatus.active);

    final channel = FakeSshSocket();
    transports.last.remoteListener!.controller.add(channel);
    await pumpEventQueue();
    channel.inbound.add(Uint8List.fromList([7, 7]));
    await pumpEventQueue();
    expect(echoData, [7, 7]);
    expect(channel.outbound, [42]);
    expect(conns[fwd.id], 1);

    await svc.stop(fwd.id);
    expect(transports.last.remoteListener!.closed, isTrue);
    await echo.close();
  });

  test('remote forward refused by server reports error', () async {
    final svc = makeService();
    transports.last.refuseRemote = true;
    final fwd = rule(type: ForwardType.remote);
    await svc.start(fwd);
    expect(lastStatus(fwd.id), ForwardStatus.error);
    expect(statuses.last.$3, 'Server refused the remote forward request');
  });

  test('dynamic forward starts SOCKS server and samples connections', () {
    fakeAsync((fa) {
      final svc = makeService();
      final fwd = rule(type: ForwardType.dynamic, localPort: 1080);
      svc.start(fwd);
      fa.flushMicrotasks();
      expect(lastStatus(fwd.id), ForwardStatus.active);

      transports.last.dynamicForward!.connectionCount = 5;
      fa.elapse(const Duration(seconds: 2));
      expect(conns[fwd.id], 5);

      svc.stop(fwd.id);
      fa.flushMicrotasks();
      expect(transports.last.dynamicForward!.closed, isTrue);
      expect(lastStatus(fwd.id), ForwardStatus.idle);
    });
  });
```

Add the import at the top of the test file:

```dart
import 'package:fake_async/fake_async.dart';
```

(`fake_async` ships transitively with flutter_test; if the analyzer complains, add `fake_async: ^1.3.0` to `dev_dependencies` in `app/pubspec.yaml`.)

- [ ] **Step 2: Run the tests**

Run: `cd app && flutter test test/services/port_forward_service_test.dart`
Expected: PASS. Fix the service if a test exposes a bug (e.g. piping direction, listener cleanup).

- [ ] **Step 3: Commit**

```bash
git add app/test/services/port_forward_service_test.dart app/pubspec.yaml
git commit -m "test(port-forward): remote and dynamic tunnel coverage"
```

---

### Task 7: PortForwardService — reconnect loop tests + helpers

**Files:**
- Test: `app/test/services/port_forward_service_test.dart` (extend)
- Modify (only if a test exposes a bug): `app/lib/services/port_forward_service.dart`

- [ ] **Step 1: Add reconnect tests:**

```dart
  test('drop triggers reconnecting then active; backoff doubles capped at 30s',
      () async {
    final svc = makeService();
    final fwd = rule();
    await svc.start(fwd);
    expect(lastStatus(fwd.id), ForwardStatus.active);
    final port = svc.localPortFor(fwd.id)!;

    acquireFailures = 5; // 5 failed dials before success
    transports.add(FakeTransport());
    transports.first.drop();
    await pumpEventQueue();

    expect(lastStatus(fwd.id), ForwardStatus.active); // re-established
    expect(
        delays,
        const [
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 16),
          Duration(seconds: 30),
          Duration(seconds: 30),
        ]);
    // Local listener kept its port across the drop.
    expect(svc.localPortFor(fwd.id), port);
    expect(
        statuses.map((s) => s.$2).toList(),
        containsAllInOrder([
          ForwardStatus.connecting,
          ForwardStatus.active,
          ForwardStatus.reconnecting,
          ForwardStatus.active,
        ]));
    await svc.stop(fwd.id);
  });

  test('stop during reconnect cancels the retry loop', () async {
    final svc = makeService();
    final fwd = rule();
    await svc.start(fwd);
    final callsAfterStart = acquireCalls;

    delayGate = Completer<void>();
    transports.first.drop();
    await pumpEventQueue();
    expect(lastStatus(fwd.id), ForwardStatus.reconnecting);

    await svc.stop(fwd.id);
    expect(lastStatus(fwd.id), ForwardStatus.idle);
    delayGate!.complete();
    await pumpEventQueue();
    expect(acquireCalls, callsAfterStart); // no re-dial after stop
  });

  test('stopForHost stops only that host\'s tunnels', () async {
    final svc = makeService();
    final a = rule();
    await svc.start(a);
    await svc.stopForHost('h1');
    expect(svc.isRunning(a.id), isFalse);
    expect(lastStatus(a.id), ForwardStatus.idle);
  });

  test('autoStartAll starts only autoStart rules', () async {
    final svc = makeService();
    final auto = rule()..autoStart = true;
    final manual = rule();
    await svc.autoStartAll([auto, manual]);
    expect(svc.isRunning(auto.id), isTrue);
    expect(svc.isRunning(manual.id), isFalse);
    await svc.stopAll();
    expect(svc.isRunning(auto.id), isFalse);
  });
```

- [ ] **Step 2: Run the tests**

Run: `cd app && flutter test test/services/port_forward_service_test.dart`
Expected: PASS. If the backoff sequence assertion fails, check `_onDropped`'s doubling order (delay first, then dial — sequence is 2,4,8,16,30,30 for 5 failures + 1 success).

- [ ] **Step 3: Commit**

```bash
git add app/test/services/port_forward_service_test.dart app/lib/services/port_forward_service.dart
git commit -m "test(port-forward): reconnect backoff, stop-during-reconnect, autostart"
```

---

### Task 8: UI — start/stop toggle, edit panel, autoStart, counters

**Files:**
- Modify: `app/lib/widgets/port_forwarding_screen.dart`
- Test: `app/test/widgets/port_forwarding_screen_test.dart` (new)

- [ ] **Step 1: Write the failing widget test:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/services/port_forward_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/port_forwarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(PortForwardProvider, Widget)> build() async {
    final provider = PortForwardProvider();
    await provider.ready;
    final service = PortForwardService(
      acquireTransport: (_) async => throw UnimplementedError(),
      resolveHost: (_) => null,
      onStatus: provider.setStatus,
      onConnections: provider.setConnections,
    );
    final widget = MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => HostProvider(StorageService())),
        Provider.value(value: service),
      ],
      child: const MaterialApp(home: Scaffold(body: PortForwardingScreen())),
    );
    return (provider, widget);
  }

  testWidgets('rule row shows start toggle, error line and conn chip',
      (tester) async {
    final (provider, widget) = await build();
    final fwd = PortForward(
        label: 'db tunnel',
        type: ForwardType.local,
        localPort: 8080,
        remoteHost: 'db',
        remotePort: 5432);
    await provider.add(fwd);

    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('db tunnel'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    provider.setStatus(fwd.id, ForwardStatus.error, error: 'Port 8080 already in use');
    await tester.pump();
    expect(find.text('Port 8080 already in use'), findsOneWidget);

    provider.setStatus(fwd.id, ForwardStatus.active);
    provider.setConnections(fwd.id, 3);
    await tester.pump();
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.text('3 conn'), findsOneWidget);
  });

  testWidgets('tapping a rule opens the edit panel prefilled', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'edit me',
        type: ForwardType.local,
        localPort: 9090,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('edit me'));
    await tester.pump();

    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'edit me'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Auto-start on launch'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/port_forwarding_screen_test.dart`
Expected: FAIL (no toggle icon, no edit panel).

- [ ] **Step 3: Implement the screen changes** in `port_forwarding_screen.dart`:

3a. Add import: `import '../services/port_forward_service.dart';`

3b. Screen state — track the rule being edited and pass callbacks:

```dart
class _PortForwardingScreenState extends State<PortForwardingScreen> {
  bool _showPanel = false;
  PortForward? _editing;

  void _openEditor([PortForward? fwd]) =>
      setState(() { _editing = fwd; _showPanel = true; });

  void _closePanel() => setState(() { _showPanel = false; _editing = null; });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortForwardProvider>();

    return Row(
      children: [
        Expanded(
          child: Container(
            color: AppColors.bg,
            child: Column(
              children: [
                _TopBar(onAdd: _openEditor),
                Expanded(
                  child: provider.forwards.isEmpty
                      ? _EmptyState(onAdd: _openEditor)
                      : ListView.builder(
                          padding: const EdgeInsets.all(24),
                          itemCount: provider.forwards.length,
                          itemBuilder: (_, i) => _ForwardTile(
                            forward: provider.forwards[i],
                            onEdit: _openEditor,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_showPanel)
          _ForwardPanel(
            key: ValueKey(_editing?.id ?? 'new'),
            initial: _editing,
            onClose: _closePanel,
            onSave: (forward) async {
              final provider = context.read<PortForwardProvider>();
              final service = context.read<PortForwardService>();
              if (_editing != null) {
                if (service.isRunning(forward.id)) await service.stop(forward.id);
                await provider.update(forward);
              } else {
                await provider.add(forward);
              }
              if (mounted) _closePanel();
            },
          ),
      ],
    );
  }
}
```

3c. `_ForwardTile` — add `onEdit` param, wrap in `GestureDetector(onTap: () => widget.onEdit(fwd))`, extend the row:

```dart
class _ForwardTile extends StatefulWidget {
  final PortForward forward;
  final void Function(PortForward) onEdit;
  const _ForwardTile({required this.forward, required this.onEdit});

  @override
  State<_ForwardTile> createState() => _ForwardTileState();
}

class _ForwardTileState extends State<_ForwardTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fwd = widget.forward;
    final statusColor = switch (fwd.status) {
      ForwardStatus.active => AppColors.accent,
      ForwardStatus.error => AppColors.red,
      ForwardStatus.connecting || ForwardStatus.reconnecting => AppColors.orange,
      ForwardStatus.idle => AppColors.textTertiary,
    };
    final running = fwd.status == ForwardStatus.active ||
        fwd.status == ForwardStatus.connecting ||
        fwd.status == ForwardStatus.reconnecting;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onEdit(fwd),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: statusColor),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(fwd.label,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        _Badge(fwd.typeLabel),
                        if (fwd.status == ForwardStatus.active) ...[
                          const SizedBox(width: 6),
                          _Badge('${fwd.activeConnections} conn'),
                        ],
                        if (fwd.status == ForwardStatus.reconnecting) ...[
                          const SizedBox(width: 6),
                          const _Badge('reconnecting…'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(fwd.summary,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    if (fwd.status == ForwardStatus.error &&
                        fwd.errorMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(fwd.errorMessage!,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              _IconAction(
                icon: running ? Icons.stop : Icons.play_arrow,
                color: running ? AppColors.red : AppColors.accent,
                onTap: () {
                  final service = context.read<PortForwardService>();
                  if (running) {
                    service.stop(fwd.id);
                  } else {
                    service.start(fwd);
                  }
                },
              ),
              if (_hovered) ...[
                const SizedBox(width: 6),
                _IconAction(
                  icon: Icons.delete_outlined,
                  color: AppColors.red,
                  onTap: () async {
                    final service = context.read<PortForwardService>();
                    final provider = context.read<PortForwardProvider>();
                    await service.stop(fwd.id);
                    await provider.delete(fwd.id);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
```

(The old hover-only delete container is replaced by `_IconAction`; the play/stop action is always visible.)

3d. `_ForwardPanel` — `initial` support + autoStart checkbox:

- Add field `final PortForward? initial;` and constructor param `this.initial`.
- Add state `bool _autoStart = false;` and:

```dart
  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _label.text = init.label;
      _localHost.text = init.localHost;
      _localPort.text = init.localPort.toString();
      _remoteHost.text = init.remoteHost;
      _remotePort.text = init.remotePort == 0 ? '' : init.remotePort.toString();
      _type = init.type;
      _selectedHostId = init.hostId;
      _autoStart = init.autoStart;
    }
  }
```

- `_submit` builds with identity + flag:

```dart
      await widget.onSave(PortForward(
        id: widget.initial?.id,
        label: _label.text.trim(),
        type: _type,
        localHost: _localHost.text.trim(),
        localPort: int.parse(_localPort.text),
        remoteHost: _remoteHost.text.trim(),
        remotePort: int.tryParse(_remotePort.text) ?? 0,
        hostId: _selectedHostId,
        autoStart: _autoStart,
      ));
```

- Host dropdown: guard against a deleted host: `initialValue: hosts.any((h) => h.id == _selectedHostId) ? _selectedHostId : null,`
- After the host dropdown, before the submit button, insert:

```dart
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => setState(() => _autoStart = !_autoStart),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _autoStart,
                            activeColor: AppColors.accent,
                            checkColor: Colors.black,
                            onChanged: (v) =>
                                setState(() => _autoStart = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Auto-start on launch',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
```

- Header title: `Text(widget.initial == null ? 'New Port Forward Rule' : 'Edit Port Forward Rule', ...)` (drop the `const` on that Text).
- Submit button label: `Text(widget.initial == null ? 'Add Rule' : 'Save', style: const TextStyle(fontWeight: FontWeight.w600))`.

- [ ] **Step 4: Run widget test + analyze**

Run: `cd app && flutter test test/widgets/port_forwarding_screen_test.dart && flutter analyze`
Expected: PASS, no issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/port_forwarding_screen.dart app/test/widgets/port_forwarding_screen_test.dart
git commit -m "feat(port-forward): start/stop toggle, edit panel, auto-start, connection chip"
```

---

### Task 9: Wiring — main.dart, HostProvider.onHostDeleted

**Files:**
- Modify: `app/lib/main.dart` (fields ~line 110, initState after line 176, provider list ~line 369, dispose ~line 326)
- Modify: `app/lib/providers/host_provider.dart` (deleteHost, ~line 82)

- [ ] **Step 1: HostProvider hook.** Next to `onMutation` (line 12) add:

```dart
  /// Fired before a host is removed so dependents (tunnels) can shut down.
  void Function(String hostId)? onHostDeleted;
```

In `deleteHost`, as the first line of the method body:

```dart
    onHostDeleted?.call(id);
```

- [ ] **Step 2: main.dart.** Add imports:

```dart
import 'providers/port_forward_provider.dart';
import 'services/port_forward_service.dart';
```

Add fields next to the other `late final` declarations:

```dart
  late final PortForwardProvider _portForwardProvider;
  late final PortForwardService _portForwardService;
```

In `initState`, directly after `_ssh.defaultHostKeyVerifier = _knownHostsProvider.verifyHostKey;` (line 176):

```dart
    _ssh.defaultKeyLookup = (id) => _keyProvider.findById(id);
    _portForwardProvider = PortForwardProvider();
    _portForwardService = PortForwardService(
      acquireTransport: (host) async =>
          SshTunnelTransport(await _ssh.ensureClient(host)),
      resolveHost: (id) =>
          _hostProvider.allHosts.where((h) => h.id == id).firstOrNull,
      onStatus: (id, status, {error}) =>
          _portForwardProvider.setStatus(id, status, error: error),
      onConnections: (id, n) => _portForwardProvider.setConnections(id, n),
    );
    _hostProvider.onHostDeleted =
        (id) => unawaited(_portForwardService.stopForHost(id));
    unawaited(_portForwardProvider.ready
        .then((_) => _portForwardService.autoStartAll(_portForwardProvider.forwards)));
```

In the provider list, replace `ChangeNotifierProvider(create: (_) => PortForwardProvider()),` with:

```dart
        ChangeNotifierProvider.value(value: _portForwardProvider),
        Provider.value(value: _portForwardService),
```

In `dispose()` (before `super.dispose()` chain at line ~326) add:

```dart
    unawaited(_portForwardService.stopAll());
```

(`dart:async` / `unawaited` is already imported in main.dart; verify, otherwise add `import 'dart:async';`.)

- [ ] **Step 3: Analyze + full test suite**

Run: `cd app && flutter analyze && flutter test`
Expected: No issues; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/main.dart app/lib/providers/host_provider.dart
git commit -m "feat(port-forward): wire runtime service, auto-start, host-delete teardown"
```

---

### Task 10: Verification + docs

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` section)

- [ ] **Step 1: Full gate**

Run: `cd app && flutter analyze && flutter test`
Expected: clean.

- [ ] **Step 2: Manual verification on macOS** (superpowers:verification-before-completion)

Run: `cd app && flutter run -d macos`
- Create a local rule (e.g. `127.0.0.1:18080 → 127.0.0.1:80` on a reachable host), press play → dot turns green; `curl localhost:18080` works; conn chip increments.
- Press stop → idle; edit the rule → panel prefilled; save persists.
- Dynamic rule on 1080 → `curl --socks5 localhost:1080 http://example.com` works.

- [ ] **Step 3: CHANGELOG** — add under `[Unreleased]` → `### Added`:

```markdown
- Port forwarding runtime: rules can now actually start/stop (local, remote, dynamic SOCKS5 tunnels) with auto-reconnect and exponential backoff, edit panel, auto-start on launch, live connection counters, and error reporting.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): port forwarding runtime"
```
