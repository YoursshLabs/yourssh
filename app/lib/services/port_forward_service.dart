import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

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

  /// In-flight transport dials keyed by host id, so two tunnels starting on
  /// the same host share one SSH connect instead of racing (the loser of that
  /// race would leak a client).
  final Map<String, Future<TunnelTransport>> _acquiring = {};

  Future<TunnelTransport> _acquire(Host host) => _acquiring.putIfAbsent(
      host.id,
      // Block body on purpose: `Map.remove` returns the stored future, and an
      // arrow body would hand it back to whenComplete — which then awaits the
      // very future it is chained on (deadlock).
      () => acquireTransport(host).whenComplete(() {
            _acquiring.remove(host.id);
          }));

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
      final transport = await _acquire(host);
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
    try {
      await t.dispose();
    } catch (_) {
      // Best-effort teardown — the tunnel is already unregistered.
    }
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
  /// start() reports failures via onStatus and never throws; rules on the
  /// same host share one dial via [_acquire], so parallel start is safe.
  Future<void> autoStartAll(Iterable<PortForward> rules) async {
    await Future.wait(rules.where((r) => r.autoStart).map(start).toList());
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
      if (!t.stopping) onConnections(t.rule.id, t.closers.length);
    };
    t.closers.add(finish);
    onConnections(t.rule.id, t.closers.length);
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
        transport = await _acquire(watcher.host);
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
          try {
            await t.dispose();
          } catch (_) {
            // Best-effort: keep re-opening the host's remaining tunnels.
          }
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
  /// The set's length is the live connection count.
  final Set<void Function()> closers = {};

  /// Tears down everything riding the (dead) SSH connection but keeps the
  /// local listener bound so a reconnect doesn't lose the port.
  Future<void> closeSshSide() async {
    for (final close in closers.toList()) {
      close();
    }
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
