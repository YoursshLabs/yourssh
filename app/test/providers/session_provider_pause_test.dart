import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _FakeClient implements SSHClient {
  _FakeClient({this.closed = false, this.pingFuture});
  final bool closed;
  final Future<void>? pingFuture;
  bool closeCalled = false;
  @override
  void close() => closeCalled = true;
  @override
  bool get isClosed => closed;
  @override
  Future<void> ping() => pingFuture ?? Future.value();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Ssh extends SshService {
  _Ssh() : super(StorageService());
  final connects = <String>[];
  final disconnects = <String>[];
  final sessionDisconnects = <String>[];
  int shellsOpened = 0;
  final shellDone = Completer<void>();
  bool connectCompletes = false;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)?
        verifyHopHostKey,
    bool Function()? isCurrent,
  }) {
    connects.add(host.id);
    if (connectCompletes) return Future.value(_FakeClient());
    return Completer<SSHClient>().future;
  }

  @override
  Future<void> openShell(SshSession session,
      {bool useTmux = false, String termType = 'xterm-256color'}) {
    shellsOpened++;
    return shellDone.future;
  }

  @override
  void disconnectSession(String sessionId) => sessionDisconnects.add(sessionId);

  @override
  void disconnect(String hostId) => disconnects.add(hostId);
}

class _ScriptedShell implements SSHSession {
  final written = <String>[];
  final _out = StreamController<Uint8List>();
  final _err = StreamController<Uint8List>();
  @override
  bool get agentForwardingRefused => false;
  @override
  Stream<Uint8List> get stdout => _out.stream;
  @override
  Stream<Uint8List> get stderr => _err.stream;
  @override
  void write(Uint8List data) => written.add(String.fromCharCodes(data));
  @override
  void resizeTerminal(int w, int h, [int pw = 0, int ph = 0]) {}
  @override
  Future<void> close() async {
    await _out.close();
    await _err.close();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ScriptedClient extends _FakeClient {
  _ScriptedClient(this.scripted);
  final _ScriptedShell scripted;
  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async =>
      scripted;
}

class _GatedSsh extends _Ssh {
  final connectGate = Completer<SSHClient>();
  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)?
        verifyHopHostKey,
    bool Function()? isCurrent,
  }) =>
      connectGate.future;
}

Host _host(String id) =>
    Host(id: id, label: id, host: '$id.com', username: 'u', detectedOs: 'ubuntu');

SshSession _session(String hostId, SessionStatus status) =>
    SshSession(host: _host(hostId), status: status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Ssh ssh;
  late SessionProvider p;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ssh = _Ssh();
    p = SessionProvider(ssh, TabMetadataService());
  });
  tearDown(() => p.dispose());

  test('pauseAll pauses connected and reconnecting sessions, closes each host once',
      () {
    final a1 = _session('A', SessionStatus.connected);
    final a2 = _session('A', SessionStatus.connecting);
    final b = _session('B', SessionStatus.connected);
    final err = _session('C', SessionStatus.error);
    final closed = _session('D', SessionStatus.disconnected);
    for (final s in [a1, a2, b, err, closed]) {
      p.addSessionForTest(s);
    }
    final dropped = <Object>[];
    p.onSessionDropped = (s, r) => dropped.add(s);

    p.pauseAll();

    for (final s in [a1, a2, b]) {
      expect(s.paused, isTrue);
      expect(s.status, SessionStatus.disconnected);
      expect(s.acceptsInput, isFalse);
    }
    expect(err.paused, isFalse);
    expect(err.status, SessionStatus.error);
    expect(closed.paused, isFalse);
    expect(ssh.disconnects, ['A', 'B']);
    // Every paused session's own shell is closed too (clients are per tab).
    expect(ssh.sessionDisconnects, unorderedEquals([a1.id, a2.id, b.id]));
    expect(dropped, isEmpty);
  });

  test('pauseAll cancels a pending reconnect and writes a dim marker', () {
    fakeAsync((fa) {
      final host = _host('A');
      final s = SshSession(host: host, status: SessionStatus.connected);
      p.addSessionForTest(s);
      p.reconnectAttempts = () => 0;
      p.autoReconnectEnabled = () => true;
      p.scheduleReconnectForTest(s);
      expect(s.status, SessionStatus.connecting);
      p.pauseAll();
      fa.elapse(const Duration(seconds: 30));
      // The countdown timer is gone: no reconnect attempt started.
      expect(ssh.connects, isEmpty);
      expect(s.status, SessionStatus.disconnected);
      expect(s.terminal.buffer.toString(),
          contains('[Paused while YourSSH was in the background]'));
      expect(s.terminal.buffer.toString(), isNot(contains('Reconnecting now')));
    });
  });

  test('a paused session whose shell closes schedules no reconnect', () async {
    ssh.connectCompletes = true;
    p.autoReconnectEnabled = () => true;
    final dropped = <Object>[];
    p.onSessionDropped = (s, r) => dropped.add(s);
    final done = p.connect(_host('A'));
    await Future<void>.delayed(Duration.zero);
    final s = p.sshSessions.single;
    expect(s.status, SessionStatus.connected);

    p.pauseAll();
    ssh.shellDone.complete();
    await done;

    expect(s.status, SessionStatus.disconnected);
    expect(s.paused, isTrue);
    expect(s.reconnectCount, 0);
    expect(s.terminal.buffer.toString(), isNot(contains('Reconnecting')));
    expect(dropped, isEmpty);
  });

  test('an attempt superseded by a pause stops quietly when it later fails',
      () async {
    p.autoReconnectEnabled = () => true;
    final failing = _GatedSsh();
    final q = SessionProvider(failing, TabMetadataService());
    addTearDown(q.dispose);
    final dropped = <Object>[];
    q.onSessionDropped = (s, r) => dropped.add(s);
    final done = q.connect(_host('A'));
    await Future<void>.delayed(Duration.zero);
    final s = q.sshSessions.single;
    expect(s.status, SessionStatus.connecting);

    q.pauseAll();
    failing.connectGate.completeError(Exception('network down'));
    await done;

    expect(s.status, SessionStatus.disconnected);
    expect(s.paused, isTrue);
    expect(s.reconnectCount, 0);
    expect(s.errorMessage, isNull);
    expect(dropped, isEmpty);
  });

  test('an attempt that succeeds after a pause stays paused and closes its client',
      () async {
    final gated = _GatedSsh();
    final q = SessionProvider(gated, TabMetadataService());
    addTearDown(q.dispose);
    final done = q.connect(_host('A'));
    await Future<void>.delayed(Duration.zero);
    final s = q.sshSessions.single;

    q.pauseAll();
    final client = _FakeClient();
    gated.connectGate.complete(client);
    await done;

    expect(client.closeCalled, isTrue);
    expect(s.status, SessionStatus.disconnected);
    expect(s.paused, isTrue);
    expect(gated.shellsOpened, 0);
  });

  test('resumePaused reconnects in tab order, stagger apart, even with auto-reconnect off',
      () {
    fakeAsync((fa) {
      p.autoReconnectEnabled = () => false;
      for (final id in ['a', 'b', 'c']) {
        p.addSessionForTest(_session(id, SessionStatus.connected));
      }
      p.pauseAll();
      p.resumePaused(stagger: const Duration(milliseconds: 300));
      fa.flushMicrotasks();
      expect(ssh.connects, ['a']);
      fa.elapse(const Duration(milliseconds: 299));
      expect(ssh.connects, ['a']);
      fa.elapse(const Duration(milliseconds: 1));
      expect(ssh.connects, ['a', 'b']);
      fa.elapse(const Duration(milliseconds: 300));
      expect(ssh.connects, ['a', 'b', 'c']);
      expect(p.sshSessions.every((s) => !s.paused), isTrue);
      expect(p.sshSessions.every((s) => s.status == SessionStatus.connecting),
          isTrue);
    });
  });

  test('paused session rejects input and nothing is buffered', () async {
    // Real SshService + a scripted shell, so sendInput really has a shell.
    final real = SshService(StorageService());
    final rp = SessionProvider(real, TabMetadataService());
    addTearDown(rp.dispose);
    final host = _host('A');
    final s = SshSession(host: host, status: SessionStatus.connected);
    rp.addSessionForTest(s);
    final shell1 = _ScriptedShell();
    real.debugSetClient(host.id, _ScriptedClient(shell1));
    unawaited(real.openShell(s));
    await Future<void>.delayed(Duration.zero);
    expect(s.acceptsInput, isTrue);
    expect(real.sendInput(s.id, 'ls\n'), isTrue);
    expect(shell1.written, ['ls\n']);

    rp.pauseAll();
    expect(s.acceptsInput, isFalse);
    expect(real.sendInput(s.id, 'rm -rf x\n'), isFalse);

    // The resumed attempt gets a fresh shell: nothing typed while paused may
    // be replayed into it.
    final shell2 = _ScriptedShell();
    real.debugSetClient(host.id, _ScriptedClient(shell2));
    s
      ..paused = false
      ..status = SessionStatus.connected;
    unawaited(real.openShell(s));
    await Future<void>.delayed(Duration.zero);
    expect(shell2.written, isEmpty);
    expect(real.sendInput(s.id, 'pwd\n'), isTrue);
    expect(shell2.written, ['pwd\n']);
    expect(shell1.written, ['ls\n']);
  });

  test('verifyLive probes only connected hosts and reconnects the dead ones',
      () async {
    ssh.connectCompletes = false;
    final alive = _session('A', SessionStatus.connected);
    final dead = _session('B', SessionStatus.connected);
    final other = _session('C', SessionStatus.connecting);
    for (final s in [alive, dead, other]) {
      p.addSessionForTest(s);
    }
    ssh.debugSetClient('A', _FakeClient());
    // B has no client -> not alive.
    await p.verifyLive(timeout: const Duration(milliseconds: 50));
    expect(ssh.disconnects, ['B']);
    expect(ssh.connects, ['B']);
    expect(alive.status, SessionStatus.connected);
    expect(other.status, SessionStatus.connecting);
    expect(dead.status, SessionStatus.connecting);
    expect(dead.paused, isFalse);
  });

  test('verifyLive probes hosts concurrently: N slow hosts cost ~one timeout',
      () {
    fakeAsync((fa) {
      ssh.connectCompletes = false;
      for (final id in ['A', 'B', 'C', 'D']) {
        p.addSessionForTest(_session(id, SessionStatus.connected));
        ssh.debugSetClient(
            id, _FakeClient(pingFuture: Completer<void>().future));
      }
      var done = false;
      unawaited(p
          .verifyLive(timeout: const Duration(seconds: 3))
          .then((_) => done = true));
      fa.elapse(const Duration(seconds: 3, milliseconds: 100));
      fa.flushMicrotasks();
      expect(done, isTrue, reason: '4 hosts x 3 s sequentially would be 12 s');
      expect(ssh.disconnects.toSet(), {'A', 'B', 'C', 'D'});
    });
  });

  group('SshService.isAlive', () {
    test('false without a client, when closed, or when ping hangs', () async {
      final s = _Ssh();
      expect(await s.isAlive('x'), isFalse);
      s.debugSetClient('x', _FakeClient(closed: true));
      expect(await s.isAlive('x'), isFalse);
      s.debugSetClient('y', _FakeClient(pingFuture: Completer<void>().future));
      expect(await s.isAlive('y', timeout: const Duration(milliseconds: 20)),
          isFalse);
      s.debugSetClient('z', _FakeClient());
      expect(await s.isAlive('z'), isTrue);
    });
  });
}
