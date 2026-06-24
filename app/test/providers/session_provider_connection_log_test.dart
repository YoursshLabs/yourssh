import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/connection_log.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _NullClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSsh extends SshService {
  _FakeSsh() : super(StorageService());
  bool failConnect = false;

  /// Keeps connect() pending so the session stays in `connecting`.
  Completer<void>? connectGate;

  /// Keeps openShell pending so a connected session doesn't drop.
  Completer<void>? shellGate;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)?
        verifyHopHostKey,
  }) async {
    final gate = connectGate;
    if (gate != null) await gate.future;
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

Host _host() => Host(label: 'prod', host: 'p.com', username: 'root');

List<String> _messages(SshSession s) =>
    s.connectionLog.map((l) => l.message).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('successful connect logs the connecting and established steps', () async {
    final p = SessionProvider(_FakeSsh(), TabMetadataService());
    await p.connect(_host());
    final s = p.sshSessions.single;

    final msgs = _messages(s);
    expect(msgs, contains('Connecting to p.com:22 as root'));
    expect(msgs, contains('Connection established'));
    p.dispose();
  });

  test('failed connect logs an error line', () async {
    final p = SessionProvider(_FakeSsh()..failConnect = true, TabMetadataService());
    await p.connect(_host());
    final s = p.sshSessions.single;

    expect(s.status, SessionStatus.error);
    expect(_messages(s).any((m) => m.startsWith('Connection failed:')), isTrue);
    expect(s.connectionLog.last.level, ConnectionLogLevel.error);
    p.dispose();
  });

  test('reconnectSession retries an errored session and clears the error', () async {
    final ssh = _FakeSsh()..failConnect = true;
    final p = SessionProvider(ssh, TabMetadataService());
    await p.connect(_host());
    final s = p.sshSessions.single;
    expect(s.status, SessionStatus.error);

    // Next attempt succeeds and the shell stays open.
    ssh.failConnect = false;
    ssh.shellGate = Completer();
    p.reconnectSession(s.id);
    await Future<void>.delayed(Duration.zero);

    expect(s.status, SessionStatus.connected);
    expect(s.errorMessage, isNull);
    expect(_messages(s), contains('Retrying connection…'));
    // A manual retry starts a fresh log — the prior attempt's failure is gone.
    expect(_messages(s).any((m) => m.startsWith('Connection failed:')), isFalse);
    expect(_messages(s).first, 'Retrying connection…');
    p.dispose();
  });

  test('reconnectSession is a no-op while already connecting', () async {
    final ssh = _FakeSsh()..connectGate = Completer();
    final p = SessionProvider(ssh, TabMetadataService());
    // Don't await: the gated connect() keeps the session in `connecting`.
    unawaited(p.connect(_host()));
    await Future<void>.delayed(Duration.zero);
    final s = p.sshSessions.single;
    expect(s.status, SessionStatus.connecting);

    final before = s.connectionLog.length;
    p.reconnectSession(s.id);
    expect(s.connectionLog.length, before); // no "Retrying…" line appended
    p.dispose();
  });
}
