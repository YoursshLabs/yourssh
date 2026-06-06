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

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    if (failConnect) throw Exception('refused');
    return _NullClient();
  }

  @override
  Future<void> openShell(SshSession session,
      {bool useTmux = false, String termType = 'xterm-256color'}) async {}

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

  test('closeSession records a user-closed disconnect', () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())..audit = audit;
    final host = _host();
    await p.connect(host);
    audit.clearAll(); // ignore the connect/drop rows from setup
    await p.connect(host);
    final id = p.sessions.last.id;
    p.closeSession(id);

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.map((e) => e.meta['reason']), contains('user-closed'));
    p.dispose();
    audit.dispose();
  });
}
