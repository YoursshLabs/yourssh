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
    expect(statuses.map((s) => s.$2),
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
