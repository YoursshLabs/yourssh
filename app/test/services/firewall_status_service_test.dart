import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/firewall_status.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/firewall_status_service.dart';
import 'package:yourssh/services/ssh_service.dart';

class _FakeSsh extends Fake implements SshService {
  final String stdout;
  _FakeSsh(this.stdout);

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async =>
      (stdout: stdout, stderr: '', exitCode: 0);
}

class _ThrowingSsh extends Fake implements SshService {
  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async =>
      throw Exception('err');
}

Host _host() => Host(
      id: 'h1',
      label: 'test',
      host: 'example.com',
      port: 22,
      username: 'root',
    );

void main() {
  group('FirewallStatusService', () {
    test('poll delivers parsed FirewallStatus via onUpdate', () async {
      FirewallStatus? got;
      final svc = FirewallStatusService(
        host: _host(),
        sshService: _FakeSsh(
          'Status: active\nDefault: deny (incoming), allow (outgoing)\n',
        ),
        onUpdate: (f) => got = f,
      );
      await svc.poll();
      expect(got, isNotNull);
      expect(got!.type, FirewallType.ufw);
      expect(got!.enabled, isTrue);
    });

    test('poll silently ignores exec exceptions', () async {
      final svc = FirewallStatusService(
        host: _host(),
        sshService: _ThrowingSsh(),
        onUpdate: (_) => fail('should not call'),
      );
      await expectLater(svc.poll(), completes);
    });

    test('poll delivers none type for __NO_FIREWALL__', () async {
      FirewallStatus? got;
      final svc = FirewallStatusService(
        host: _host(),
        sshService: _FakeSsh('__NO_FIREWALL__'),
        onUpdate: (f) => got = f,
      );
      await svc.poll();
      expect(got!.type, FirewallType.none);
    });

    test('stop cancels the timer', () async {
      int callCount = 0;
      final svc = FirewallStatusService(
        host: _host(),
        sshService: _FakeSsh('__NO_FIREWALL__'),
        onUpdate: (_) => callCount++,
      );
      svc.start(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      svc.stop();
      final countAtStop = callCount;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(callCount, countAtStop);
    });

    test('onError callback is invoked on exec exception', () async {
      Object? caughtError;
      final svc = FirewallStatusService(
        host: _host(),
        sshService: _ThrowingSsh(),
        onUpdate: (_) => fail('should not call onUpdate'),
        onError: (e) => caughtError = e,
      );
      await svc.poll();
      expect(caughtError, isNotNull);
    });
  });
}
