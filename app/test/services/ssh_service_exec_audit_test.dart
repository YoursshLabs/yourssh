import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

class _ExecClient implements SSHClient {
  @override
  bool get isClosed => false;

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    final out = Uint8List.fromList('out'.codeUnits);
    return SSHRunResult(
        output: out,
        stdout: out,
        stderr: Uint8List(0),
        exitCode: 0,
        exitSignal: null);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('exec records a redacted audit event with source and exit code',
      () async {
    final audit = AuditService()..initInMemory();
    final svc = SshService(StorageService())..audit = audit;
    final host = Host(label: 'prod', host: 'p.com', username: 'root');
    svc.debugSetClient(host.id, _ExecClient());

    await svc.exec(host, 'export TOKEN=abc && ls', auditSource: 'bulk');

    final rows = audit.query(const AuditFilter(type: 'exec'));
    expect(rows.length, 1);
    expect(rows.single.command, 'export TOKEN=[REDACTED] && ls');
    expect(rows.single.exitCode, 0);
    expect(rows.single.hostLabel, 'prod');
    expect(rows.single.meta['source'], 'bulk');
    audit.dispose();
  });

  test('default source is app; auditSource null skips auditing', () async {
    final audit = AuditService()..initInMemory();
    final svc = SshService(StorageService())..audit = audit;
    final host = Host(label: 'h', host: 'h.com', username: 'u');
    svc.debugSetClient(host.id, _ExecClient());

    await svc.exec(host, 'uptime');
    await svc.exec(host, 'cat /proc/net/dev', auditSource: null);

    final rows = audit.query(const AuditFilter(type: 'exec'));
    expect(rows.length, 1);
    expect(rows.single.meta['source'], 'app');
    audit.dispose();
  });
}
