import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _NullClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSsh extends SshService {
  _FakeSsh({this.failConnect = false}) : super(StorageService());
  final bool failConnect;

  /// When set, openShell blocks until completed — keeps the session in
  /// `connected` state so user-close paths can be exercised.
  Completer<void>? shellGate;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    if (failConnect) throw Exception('refused');
    return _NullClient();
  }

  @override
  Future<void> openShell(SshSession session,
      {bool useTmux = false, String termType = 'xterm-256color'}) async {
    final gate = shellGate;
    if (gate != null) await gate.future;
  }

  @override
  void disconnectSession(String sessionId) {}

  @override
  void disconnect(String hostId) {}
}

Host _host() =>
    Host(label: 'prod', host: 'p.com', username: 'root', detectedOs: 'ubuntu');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('successful connect records a connect event', () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())..audit = audit;
    await p.connect(_host());

    final connects = audit.query(const AuditFilter(type: 'connect'));
    expect(connects.length, 1);
    expect(connects.single.hostLabel, 'prod');
    expect(connects.single.meta.containsKey('error'), isFalse);
    p.dispose();
    audit.dispose();
  });

  test('final connect failure records connect with error; no spam', () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(failConnect: true), TabMetadataService())
      ..audit = audit;
    // auto-reconnect off → first failure is final
    await p.connect(_host());

    final connects = audit.query(const AuditFilter(type: 'connect'));
    expect(connects.length, 1);
    expect(connects.single.meta['error'], contains('refused'));
    expect(connects.single.meta['attempts'], 1);
    p.dispose();
    audit.dispose();
  });

  test('shell close without reconnect records a dropped disconnect',
      () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())..audit = audit;
    await p.connect(_host()); // openShell returns immediately → drop path

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.length, 1);
    expect(dis.single.meta['reason'], 'dropped');
    p.dispose();
    audit.dispose();
  });

  test('drop with auto-reconnect ON still records a disconnect (paired log)',
      () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())..audit = audit;
    p.autoReconnectEnabled = () => true;
    p.reconnectAttempts = () => 0; // unlimited
    await p.connect(_host()); // openShell returns → drop → reconnect scheduled

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.length, 1,
        reason: 'a flapping host must log disconnects, not just connects');
    expect(dis.single.meta['reason'], 'dropped');
    expect(dis.single.meta['reconnecting'], isTrue);
    p.dispose();
    audit.dispose();
  });

  test('closing an already-dropped tab does NOT write a second disconnect',
      () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())..audit = audit;
    await p.connect(_host()); // drop path already wrote disconnect{dropped}
    expect(
        audit.query(const AuditFilter(type: 'disconnect')).length, 1);

    p.closeSession(p.sessions.single.id); // tab is dead (disconnected)

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.length, 1,
        reason: 'user-closing a dead tab must not double-count disconnects');
    p.dispose();
    audit.dispose();
  });

  test('closeSession on a LIVE session records a user-closed disconnect',
      () async {
    final audit = AuditService()..initInMemory();
    final ssh = _FakeSsh()..shellGate = Completer<void>();
    final p = SessionProvider(ssh, TabMetadataService())..audit = audit;

    unawaited(p.connect(_host())); // shell stays open behind the gate
    await pumpEventQueue();
    expect(p.sshSessions.single.status, SessionStatus.connected);

    p.closeSession(p.sessions.single.id);

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.map((e) => e.meta['reason']), contains('user-closed'));

    ssh.shellGate!.complete(); // release the blocked openShell
    await pumpEventQueue();
    p.dispose();
    audit.dispose();
  });
}
