import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/system_snapshot.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/system_stats_service.dart';

class _FakeSsh extends Fake implements SshService {
  final String stdout;
  int callCount = 0;

  _FakeSsh(this.stdout);

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async {
    callCount++;
    return (stdout: stdout, stderr: '', exitCode: 0);
  }
}

class _ThrowingSsh extends Fake implements SshService {
  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async {
    throw Exception('disconnected');
  }
}

Host _host() => Host(
      id: 'h1',
      label: 'test',
      host: 'example.com',
      port: 22,
      username: 'root',
    );

const _kOutput = '''
__CPU1__
cpu  100 0 0 900 0 0 0 0 0 0
__CPU2__
cpu  110 0 0 910 0 0 0 0 0 0
__MEM__
MemTotal:       2048000 kB
MemAvailable:   1024000 kB
__DISK__
Filesystem 1K-blocks Used Available Use% Mounted on
/dev/sda1  100000    50000 50000    50% /
__UPTIME__
3600.0 1800.0
__PORTS__
''';

void main() {
  group('SystemStatsService', () {
    test('poll delivers parsed snapshot via onUpdate', () async {
      SystemSnapshot? got;
      final svc = SystemStatsService(
        host: _host(),
        sshService: _FakeSsh(_kOutput),
        onUpdate: (s) => got = s,
      );
      await svc.poll();
      expect(got, isNotNull);
      expect(got!.disks.length, 1);
      expect(got!.uptime, const Duration(hours: 1));
      expect(got!.totalMemBytes, 2048000 * 1024);
    });

    test('poll silently ignores exec exceptions', () async {
      final svc = SystemStatsService(
        host: _host(),
        sshService: _ThrowingSsh(),
        onUpdate: (_) => fail('should not call onUpdate'),
      );
      await expectLater(svc.poll(), completes);
    });

    test('poll not called before start()', () async {
      final ssh = _FakeSsh(_kOutput);
      SystemStatsService(host: _host(), sshService: ssh, onUpdate: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ssh.callCount, 0);
    });

    test('stop() cancels the timer', () async {
      final ssh = _FakeSsh(_kOutput);
      final svc = SystemStatsService(
        host: _host(),
        sshService: ssh,
        onUpdate: (_) {},
      );
      svc.start(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      svc.stop();
      final countAfterStop = ssh.callCount;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ssh.callCount, countAfterStop);
    });
  });
}
