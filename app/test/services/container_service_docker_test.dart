import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Minimal SshService stub: override only exec and execStream.
class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;
  Stream<String> Function(String cmd)? streamStub;
  String? lastAuditSource;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host, String cmd, {String? auditSource}) async {
    lastAuditSource = auditSource;
    return execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) {
    lastAuditSource = auditSource;
    return streamStub?.call(cmd) ?? const Stream.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  group('streamDockerLogs', () {
    test('passes correct command with tail flag and stderr merge', () {
      final fake = _FakeSshService();
      String? capturedCmd;
      fake.streamStub = (cmd) {
        capturedCmd = cmd;
        return const Stream.empty();
      };
      final svc = ContainerService(fake);
      svc.streamDockerLogs(host, 'abc123', tail: 50);
      expect(capturedCmd, 'docker logs -f --tail=50 abc123 2>&1');
    });

    test('default tail is 100', () {
      final fake = _FakeSshService();
      String? capturedCmd;
      fake.streamStub = (cmd) { capturedCmd = cmd; return const Stream.empty(); };
      ContainerService(fake).streamDockerLogs(host, 'xyz');
      expect(capturedCmd, 'docker logs -f --tail=100 xyz 2>&1');
    });
  });

  group('stopContainer', () {
    test('does not throw on exit 0', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
      await expectLater(ContainerService(fake).stopContainer(host, 'c1'), completes);
    });

    test('throws Exception with stderr on exit 1', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: 'No such container: c1', exitCode: 1);
      await expectLater(
        ContainerService(fake).stopContainer(host, 'c1'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('No such container'))));
    });

    test('passes correct command', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).stopContainer(host, 'abc');
      expect(cmd, 'docker stop abc');
    });
  });

  group('startContainer', () {
    test('does not throw on exit 0', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
      await expectLater(ContainerService(fake).startContainer(host, 'c1'), completes);
    });

    test('throws on exit 1', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: 'Error response', exitCode: 1);
      await expectLater(ContainerService(fake).startContainer(host, 'c1'),
          throwsException);
    });

    test('passes correct command', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).startContainer(host, 'abc');
      expect(cmd, 'docker start abc');
    });
  });

  group('restartContainer', () {
    test('passes correct command', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).restartContainer(host, 'abc');
      expect(cmd, 'docker restart abc');
    });

    test('throws on failure', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: 'oops', exitCode: 1);
      await expectLater(ContainerService(fake).restartContainer(host, 'c1'),
          throwsException);
    });
  });

  group('auditSource', () {
    test('container calls carry auditSource devops', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
      final svc = ContainerService(fake);
      await svc.stopContainer(host, 'c1');
      expect(fake.lastAuditSource, 'devops');
      svc.streamDockerLogs(host, 'c1');
      expect(fake.lastAuditSource, 'devops');
    });
  });
}
