import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/container_entry.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;
  Stream<String> Function(String cmd)? streamStub;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host, String cmd, {String? auditSource}) async =>
      execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) =>
      streamStub?.call(cmd) ?? const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  // ── parseComposeLs ─────────────────────────────────────

  group('parseComposeLs', () {
    test('parses valid JSON array', () {
      const json = '[{"Name":"proj","Status":"running(2)","ConfigFiles":"/opt/proj/compose.yml"}]';
      final stacks = ContainerService.parseComposeLs(json);
      expect(stacks.length, 1);
      expect(stacks[0].name, 'proj');
      expect(stacks[0].projectDir, '/opt/proj');
      expect(stacks[0].status, 'running(2)');
    });

    test('returns empty list for empty array', () {
      expect(ContainerService.parseComposeLs('[]'), isEmpty);
    });

    test('returns empty list for malformed JSON', () {
      expect(ContainerService.parseComposeLs('not-json'), isEmpty);
    });

    test('returns empty list for empty string', () {
      expect(ContainerService.parseComposeLs(''), isEmpty);
    });

    test('uses dirname of first ConfigFiles entry as projectDir', () {
      const json = '[{"Name":"x","Status":"exited(1)","ConfigFiles":"/srv/app/docker-compose.yml,/srv/app/override.yml"}]';
      final stacks = ContainerService.parseComposeLs(json);
      expect(stacks[0].projectDir, '/srv/app');
    });

    test('a slash-less ConfigFiles entry is skipped, not fatal to the list', () {
      const json =
          '[{"Name":"bad","Status":"x","ConfigFiles":"compose.yml"},'
          '{"Name":"good","Status":"running(1)","ConfigFiles":"/opt/good/compose.yml"}]';
      final stacks = ContainerService.parseComposeLs(json);
      expect(stacks.length, 1);
      expect(stacks[0].name, 'good');
      expect(stacks[0].projectDir, '/opt/good');
    });
  });

  // ── parseComposeFindOutput ──────────────────────────────

  group('parseComposeFindOutput', () {
    test('parses find output into stacks', () {
      const output = '/home/user/myapp/docker-compose.yml\n/opt/blog/compose.yml\n';
      final stacks = ContainerService.parseComposeFindOutput(output);
      expect(stacks.length, 2);
      expect(stacks[0].projectDir, '/home/user/myapp');
      expect(stacks[0].name, 'myapp');
      expect(stacks[0].status, 'unknown');
      expect(stacks[1].projectDir, '/opt/blog');
    });

    test('deduplicates by projectDir', () {
      const output =
          '/opt/proj/docker-compose.yml\n/opt/proj/docker-compose.override.yml\n';
      final stacks = ContainerService.parseComposeFindOutput(output);
      expect(stacks.length, 1);
    });

    test('returns empty list for empty output', () {
      expect(ContainerService.parseComposeFindOutput(''), isEmpty);
    });

    test('skips root-level compose file with empty projectDir', () {
      // /compose.yml → lastSlash=0 → projectDir='' → must be filtered out
      const output = '/compose.yml\n/opt/app/compose.yml\n';
      final stacks = ContainerService.parseComposeFindOutput(output);
      expect(stacks.length, 1);
      expect(stacks[0].projectDir, '/opt/app');
    });
  });

  // ── parseComposePs ──────────────────────────────────────

  group('parseComposePs', () {
    test('parses JSONL output (one JSON object per line)', () {
      const output =
          '{"Name":"myapp-web-1","Service":"web","State":"running","Image":"nginx:latest"}\n'
          '{"Name":"myapp-db-1","Service":"db","State":"running","Image":"postgres:15"}\n';
      final services = ContainerService.parseComposePs(output);
      expect(services.length, 2);
      expect(services[0].name, 'web');
      expect(services[0].status, 'running');
      expect(services[0].image, 'nginx:latest');
    });

    test('parses JSON array output', () {
      const output =
          '[{"Name":"myapp-web-1","Service":"web","State":"running","Image":"nginx:latest"}]';
      final services = ContainerService.parseComposePs(output);
      expect(services.length, 1);
      expect(services[0].name, 'web');
    });

    test('aggregates replicas for same service name', () {
      const output =
          '{"Name":"app-worker-1","Service":"worker","State":"running","Image":"myimg"}\n'
          '{"Name":"app-worker-2","Service":"worker","State":"running","Image":"myimg"}\n';
      final services = ContainerService.parseComposePs(output);
      expect(services.length, 1);
      expect(services[0].replicas, 2);
    });

    test('returns empty list for empty output', () {
      expect(ContainerService.parseComposePs(''), isEmpty);
    });

    test('returns empty list for malformed JSON', () {
      expect(ContainerService.parseComposePs('garbage'), isEmpty);
    });

    test('aggregates all-running replicas as running', () {
      const output =
          '{"Name":"app-worker-1","Service":"worker","State":"running","Image":"myimg"}\n'
          '{"Name":"app-worker-2","Service":"worker","State":"running","Image":"myimg"}\n';
      final services = ContainerService.parseComposePs(output);
      expect(services.length, 1);
      expect(services[0].status, 'running');
      expect(services[0].replicas, 2);
    });

    test('marks degraded service when some replicas running and some exited', () {
      const output =
          '{"Name":"app-web-1","Service":"web","State":"running","Image":"nginx"}\n'
          '{"Name":"app-web-2","Service":"web","State":"exited","Image":"nginx"}\n';
      final services = ContainerService.parseComposePs(output);
      expect(services.length, 1);
      expect(services[0].status, 'degraded');
      expect(services[0].replicas, 2);
    });
  });

  // ── listComposeServices ────────────────────────────────

  group('listComposeServices', () {
    test('passes correct command', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '[]', stderr: '', exitCode: 0); };
      await ContainerService(fake).listComposeServices(
          host, ComposeStack(name: 'a', projectDir: '/opt/app', status: 'x'));
      expect(cmd, "cd '/opt/app' && docker compose ps --format json 2>/dev/null");
    });

    test('throws on non-zero exit', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: 'boom', exitCode: 1);
      await expectLater(
        ContainerService(fake).listComposeServices(
            host, ComposeStack(name: 'a', projectDir: '/p', status: 'x')),
        throwsException);
    });
  });

  // ── discoverComposeStacks dedup ─────────────────────────

  group('discoverComposeStacks', () {
    test('deduplicates by projectDir: ls result takes precedence over find', () async {
      final fake = _FakeSshService();
      // First cmd: docker compose ls; second: find
      fake.execStub = (cmd) {
        if (cmd.contains('docker compose ls')) {
          return (
            stdout: '[{"Name":"myapp","Status":"running(1)","ConfigFiles":"/opt/myapp/compose.yml"}]',
            stderr: '',
            exitCode: 0,
          );
        }
        // find output — same projectDir
        return (stdout: '/opt/myapp/compose.yml\n', stderr: '', exitCode: 0);
      };
      final svc = ContainerService(fake);
      final stacks = await svc.discoverComposeStacks(host);
      // Both sources found /opt/myapp — should appear once only, with status from ls
      final myapp = stacks.where((s) => s.projectDir == '/opt/myapp').toList();
      expect(myapp.length, 1);
      expect(myapp[0].status, 'running(1)');
    });
  });

  // ── compose actions ─────────────────────────────────────

  group('composeUp', () {
    test('runs docker compose up -d in projectDir', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      final stack = ComposeStack(name: 'app', projectDir: '/opt/app', status: 'exited');
      await ContainerService(fake).composeUp(host, stack);
      expect(cmd, "cd '/opt/app' && docker compose up -d");
    });

    test('throws on non-zero exit', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: 'pull error', exitCode: 1);
      await expectLater(
        ContainerService(fake).composeUp(host,
            ComposeStack(name: 'a', projectDir: '/p', status: 'x')),
        throwsException);
    });
  });

  group('composeDown', () {
    test('runs docker compose down in projectDir', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).composeDown(
          host, ComposeStack(name: 'a', projectDir: '/srv/a', status: 'x'));
      expect(cmd, "cd '/srv/a' && docker compose down");
    });
  });

  group('startComposeService / stopComposeService', () {
    test('start passes service name', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).startComposeService(
          host, ComposeStack(name: 'app', projectDir: '/p', status: 'x'), 'web');
      expect(cmd, "cd '/p' && docker compose start 'web'");
    });

    test('stop passes service name', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).stopComposeService(
          host, ComposeStack(name: 'app', projectDir: '/p', status: 'x'), 'web');
      expect(cmd, "cd '/p' && docker compose stop 'web'");
    });
  });

  group('streamComposeServiceLogs', () {
    test('passes correct command with tail and service name', () {
      final fake = _FakeSshService();
      String? cmd;
      fake.streamStub = (c) { cmd = c; return const Stream.empty(); };
      ContainerService(fake).streamComposeServiceLogs(
          host, ComposeStack(name: 'app', projectDir: '/opt/app', status: 'x'), 'web',
          tail: 50);
      expect(cmd, "cd '/opt/app' && docker compose logs -f --tail=50 'web' 2>&1");
    });
  });

  // ── shell quoting (_shq) ────────────────────────────────

  group('shell quoting via composeUp', () {
    test('quote-free projectDir produces unchanged single-quoted command', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).composeUp(
          host, ComposeStack(name: 'app', projectDir: '/opt/app', status: 'x'));
      expect(cmd, "cd '/opt/app' && docker compose up -d");
    });

    test('projectDir with single quote is properly escaped', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).composeUp(
          host, ComposeStack(name: "a'b", projectDir: "/opt/a'b", status: 'x'));
      expect(cmd, r"cd '/opt/a'\''b' && docker compose up -d");
    });
  });

  // ── validateComposeFile ─────────────────────────────────

  group('validateComposeFile', () {
    test('passes correct command and returns service names', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) {
        cmd = c;
        return (stdout: 'web\ndb\n', stderr: '', exitCode: 0);
      };
      final names = await ContainerService(fake)
          .validateComposeFile(host, '/opt/app/compose.yml');
      expect(cmd, "docker compose -f '/opt/app/compose.yml' config --services 2>&1");
      expect(names, ['web', 'db']);
    });

    test('throws on non-zero exit', () async {
      final fake = _FakeSshService();
      fake.execStub = (_) => (stdout: '', stderr: 'no compose file', exitCode: 1);
      await expectLater(
        ContainerService(fake).validateComposeFile(host, '/bad/path.yml'),
        throwsException,
      );
    });
  });
}
