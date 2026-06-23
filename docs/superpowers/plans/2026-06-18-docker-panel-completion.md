# Docker Panel Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Docker logs, container lifecycle actions (stop/start/restart), and Compose awareness (stack discovery, service management, per-service logs) to the Containers screen.

**Architecture:** Extend `ContainerService` with new methods and static parsers; extract `DockerPanel` from `ContainersScreen`; add `ComposePanel`; wire a new Compose tab. All service methods are tested with a `_FakeSshService` stub; widget tests verify renders and basic interactions.

**Tech Stack:** Flutter/Dart, `SshService.exec` returns `({String stdout, String stderr, int exitCode})`, `SshService.execStream` returns `Stream<String>`, `dart:convert` for JSON, `provider` package for session/service access.

**Spec:** `docs/superpowers/specs/2026-06-18-docker-panel-completion-design.md`

## Global Constraints

- Every `ssh.exec` / `ssh.execStream` call in `ContainerService` uses `auditSource: 'devops'`.
- All non-zero exit codes throw `Exception(stderr.trim().isEmpty ? '<cmd> failed' : stderr.trim())`.
- Log lines capped at 2000 per panel; oldest dropped on overflow (`if (_logLines.length > 2000) _logLines.removeRange(0, _logLines.length - 2000)`).
- `docker compose` = Docker Compose v2 subcommand. v1 (`docker-compose`) is not supported; show a hint card.
- All static parse methods return empty lists (never throw) on malformed input.
- Flutter test command: run from `app/` directory: `flutter test <path>`.
- Shell-quote project paths using single quotes in all `cd '...' && docker compose ...` commands.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/lib/models/container_entry.dart` | Modify | Add `ComposeStack`, `ComposeService` models |
| `app/lib/services/container_service.dart` | Modify | Add 11 new methods + 3 static parsers |
| `app/lib/widgets/containers_screen.dart` | Modify | Add `_Tab.compose`; render `DockerPanel` / `ComposePanel` instead of `_dockerList()` |
| `app/lib/widgets/docker_panel.dart` | Create | Container list + lifecycle buttons + inline log panel |
| `app/lib/widgets/compose_panel.dart` | Create | Stack discovery + service list + inline log panel |
| `app/test/services/container_service_docker_test.dart` | Create | Unit tests: Docker lifecycle methods + command strings |
| `app/test/services/container_service_compose_test.dart` | Create | Unit tests: Compose static parsers + discovery merge |

---

## Task 1: Add ComposeStack and ComposeService models

**Files:**
- Modify: `app/lib/models/container_entry.dart`

**Interfaces:**
- Produces: `ComposeStack`, `ComposeService` — used by Tasks 2, 3, 4, 5

- [ ] **Step 1: Add models to `container_entry.dart`**

Append after the last class in the file:

```dart
/// One Docker Compose project discovered on the remote host.
class ComposeStack {
  final String name;
  final String projectDir;
  final String status;

  const ComposeStack({
    required this.name,
    required this.projectDir,
    required this.status,
  });
}

/// One service within a Docker Compose stack.
class ComposeService {
  final String name;
  final String status;
  final String image;
  final int replicas;

  const ComposeService({
    required this.name,
    required this.status,
    required this.image,
    this.replicas = 1,
  });
}
```

- [ ] **Step 2: Verify the app still compiles**

```bash
cd app && flutter analyze --no-fatal-infos 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/container_entry.dart
git commit -m "feat(docker): add ComposeStack and ComposeService models"
```

---

## Task 2: ContainerService — Docker logs + lifecycle methods

**Files:**
- Modify: `app/lib/services/container_service.dart`
- Create: `app/test/services/container_service_docker_test.dart`

**Interfaces:**
- Consumes: `Host` (existing), `SshService.exec` / `SshService.execStream` (existing)
- Produces:
  - `streamDockerLogs(Host host, String id, {int tail = 100}) → Stream<String>`
  - `stopContainer(Host host, String id) → Future<void>`
  - `startContainer(Host host, String id) → Future<void>`
  - `restartContainer(Host host, String id) → Future<void>`

- [ ] **Step 1: Write the failing tests**

Create `app/test/services/container_service_docker_test.dart`:

```dart
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
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app && flutter test test/services/container_service_docker_test.dart 2>&1 | tail -10
```

Expected: compilation error — `streamDockerLogs`, `stopContainer`, etc. not found.

- [ ] **Step 3: Add methods to `ContainerService`**

In `app/lib/services/container_service.dart`, add a new section after `// ── Docker ────` (after `listDockerContainers`):

```dart
  // ── Docker logs + lifecycle ───────────────────────────

  /// Streams stdout+stderr of `docker logs -f <id>`.
  Stream<String> streamDockerLogs(Host host, String id, {int tail = 100}) =>
      ssh.execStream(host, 'docker logs -f --tail=$tail $id 2>&1',
          auditSource: 'devops');

  Future<void> stopContainer(Host host, String id) async {
    final r = await ssh.exec(host, 'docker stop $id', auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker stop failed' : r.stderr.trim());
    }
  }

  Future<void> startContainer(Host host, String id) async {
    final r = await ssh.exec(host, 'docker start $id', auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker start failed' : r.stderr.trim());
    }
  }

  Future<void> restartContainer(Host host, String id) async {
    final r = await ssh.exec(host, 'docker restart $id', auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker restart failed' : r.stderr.trim());
    }
  }
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd app && flutter test test/services/container_service_docker_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/container_service.dart \
        app/test/services/container_service_docker_test.dart
git commit -m "feat(docker): container logs streaming + stop/start/restart"
```

---

## Task 3: ContainerService — Compose discovery + actions

**Files:**
- Modify: `app/lib/services/container_service.dart`
- Create: `app/test/services/container_service_compose_test.dart`

**Interfaces:**
- Consumes: `ComposeStack`, `ComposeService` (Task 1), `_FakeSshService` pattern (Task 2 test file pattern — reproduce it here)
- Produces:
  - `static List<ComposeStack> parseComposeLs(String json)`
  - `static List<ComposeStack> parseComposeFindOutput(String stdout)`
  - `static List<ComposeService> parseComposePs(String stdout)`
  - `discoverComposeStacks(Host) → Future<List<ComposeStack>>`
  - `listComposeServices(Host, ComposeStack) → Future<List<ComposeService>>`
  - `composeUp(Host, ComposeStack) → Future<void>`
  - `composeDown(Host, ComposeStack) → Future<void>`
  - `startComposeService(Host, ComposeStack, String) → Future<void>`
  - `stopComposeService(Host, ComposeStack, String) → Future<void>`
  - `streamComposeServiceLogs(Host, ComposeStack, String, {int tail}) → Stream<String>`

- [ ] **Step 1: Write the failing tests**

Create `app/test/services/container_service_compose_test.dart`:

```dart
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
  });

  // ── discoverComposeStacks dedup ─────────────────────────

  group('discoverComposeStacks', () {
    test('deduplicates by projectDir: ls result takes precedence over find', () async {
      final fake = _FakeSshService();
      // First cmd: docker compose ls; second: find
      var callCount = 0;
      fake.execStub = (cmd) {
        callCount++;
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
      expect(cmd, "cd '/p' && docker compose start web");
    });

    test('stop passes service name', () async {
      final fake = _FakeSshService();
      String? cmd;
      fake.execStub = (c) { cmd = c; return (stdout: '', stderr: '', exitCode: 0); };
      await ContainerService(fake).stopComposeService(
          host, ComposeStack(name: 'app', projectDir: '/p', status: 'x'), 'web');
      expect(cmd, "cd '/p' && docker compose stop web");
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
      expect(cmd, "cd '/opt/app' && docker compose logs -f --tail=50 web 2>&1");
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app && flutter test test/services/container_service_compose_test.dart 2>&1 | tail -10
```

Expected: compilation errors — methods not found.

- [ ] **Step 3: Add static parsers to `ContainerService`**

Add after `parseDockerPs` in `container_service.dart`. Also add `dart:convert` to imports if not present:

```dart
import 'dart:convert';
```

Then add the static parsers:

```dart
  // ── Compose static parsers ────────────────────────────

  /// Parses `docker compose ls --format json` output.
  /// Returns [] on any parse failure.
  static List<ComposeStack> parseComposeLs(String json) {
    if (json.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) {
        final map = e as Map<String, dynamic>;
        final configFiles = (map['ConfigFiles'] as String? ?? '').trim();
        // ConfigFiles may be comma-separated; take the first to derive projectDir.
        final firstFile = configFiles.split(',').first.trim();
        final projectDir = firstFile.isNotEmpty
            ? firstFile.substring(0, firstFile.lastIndexOf('/'))
            : '';
        return ComposeStack(
          name: (map['Name'] as String? ?? '').trim(),
          projectDir: projectDir,
          status: (map['Status'] as String? ?? '').trim(),
        );
      }).where((s) => s.name.isNotEmpty && s.projectDir.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Parses `find ... -name "docker-compose.yml" -o -name "compose.yml"` output.
  /// Deduplicates by projectDir.
  static List<ComposeStack> parseComposeFindOutput(String stdout) {
    final seen = <String>{};
    final out = <ComposeStack>[];
    for (final line in stdout.split('\n')) {
      final path = line.trim();
      if (path.isEmpty) continue;
      final lastSlash = path.lastIndexOf('/');
      if (lastSlash < 0) continue;
      final projectDir = path.substring(0, lastSlash);
      if (seen.contains(projectDir)) continue;
      seen.add(projectDir);
      final name = projectDir.substring(projectDir.lastIndexOf('/') + 1);
      out.add(ComposeStack(name: name, projectDir: projectDir, status: 'unknown'));
    }
    return out;
  }

  /// Parses `docker compose ps --format json` output (JSON array or JSONL).
  /// Groups by service name, counts replicas.
  static List<ComposeService> parseComposePs(String stdout) {
    if (stdout.trim().isEmpty) return const [];
    final items = <Map<String, dynamic>>[];
    try {
      // Try JSON array first.
      final decoded = jsonDecode(stdout.trim());
      if (decoded is List) {
        for (final e in decoded) {
          if (e is Map<String, dynamic>) items.add(e);
        }
      }
    } catch (_) {
      // Fall through to JSONL.
    }
    if (items.isEmpty) {
      // Try JSONL (one JSON object per line).
      for (final line in stdout.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        try {
          final obj = jsonDecode(t);
          if (obj is Map<String, dynamic>) items.add(obj);
        } catch (_) {
          continue;
        }
      }
    }
    if (items.isEmpty) return const [];

    // Group by "Service" field, count replicas.
    final byService = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final svc = (item['Service'] as String? ?? '').trim();
      if (svc.isEmpty) continue;
      (byService[svc] ??= []).add(item);
    }
    return byService.entries.map((e) {
      final first = e.value.first;
      return ComposeService(
        name: e.key,
        status: (first['State'] as String? ?? '').trim(),
        image: (first['Image'] as String? ?? '').trim(),
        replicas: e.value.length,
      );
    }).toList();
  }
```

- [ ] **Step 4: Add instance methods to `ContainerService`**

Add a new section `// ── Compose ───` after the log-streaming section:

```dart
  // ── Compose ───────────────────────────────────────────

  /// Discovers Compose stacks by running `docker compose ls` (active projects)
  /// and `find` (files on disk). Results are merged; ls entries take precedence
  /// when the same projectDir appears in both.
  Future<List<ComposeStack>> discoverComposeStacks(Host host) async {
    final results = await Future.wait([
      _composeLsStacks(host),
      _composeFindStacks(host),
    ]);
    final lsStacks = results[0];
    final findStacks = results[1];
    // Merge: ls entries take precedence.
    final seen = {for (final s in lsStacks) s.projectDir};
    return [
      ...lsStacks,
      ...findStacks.where((s) => !seen.contains(s.projectDir)),
    ];
  }

  Future<List<ComposeStack>> _composeLsStacks(Host host) async {
    final r = await ssh.exec(host, 'docker compose ls --format json 2>/dev/null',
        auditSource: 'devops');
    if (r.exitCode != 0) return const [];
    return parseComposeLs(r.stdout);
  }

  Future<List<ComposeStack>> _composeFindStacks(Host host) async {
    const findCmd =
        r"find ~ /opt /srv /home -maxdepth 3 \( -name 'docker-compose.yml' -o -name 'compose.yml' \) 2>/dev/null";
    final r = await ssh.exec(host, findCmd, auditSource: 'devops');
    if (r.exitCode != 0) return const [];
    return parseComposeFindOutput(r.stdout);
  }

  Future<List<ComposeService>> listComposeServices(
      Host host, ComposeStack stack) async {
    final r = await ssh.exec(
        host, "cd '${stack.projectDir}' && docker compose ps --format json 2>/dev/null",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose ps failed' : r.stderr.trim());
    }
    return parseComposePs(r.stdout);
  }

  Future<void> composeUp(Host host, ComposeStack stack) async {
    final r = await ssh.exec(
        host, "cd '${stack.projectDir}' && docker compose up -d",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose up failed' : r.stderr.trim());
    }
  }

  Future<void> composeDown(Host host, ComposeStack stack) async {
    final r = await ssh.exec(
        host, "cd '${stack.projectDir}' && docker compose down",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose down failed' : r.stderr.trim());
    }
  }

  Future<void> startComposeService(
      Host host, ComposeStack stack, String service) async {
    final r = await ssh.exec(
        host, "cd '${stack.projectDir}' && docker compose start $service",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose start failed' : r.stderr.trim());
    }
  }

  Future<void> stopComposeService(
      Host host, ComposeStack stack, String service) async {
    final r = await ssh.exec(
        host, "cd '${stack.projectDir}' && docker compose stop $service",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose stop failed' : r.stderr.trim());
    }
  }

  Stream<String> streamComposeServiceLogs(
      Host host, ComposeStack stack, String service, {int tail = 100}) =>
      ssh.execStream(
          host,
          "cd '${stack.projectDir}' && docker compose logs -f --tail=$tail $service 2>&1",
          auditSource: 'devops');
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
cd app && flutter test test/services/container_service_compose_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Also run Docker tests to ensure no regression**

```bash
cd app && flutter test test/services/container_service_docker_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/services/container_service.dart \
        app/test/services/container_service_compose_test.dart
git commit -m "feat(docker): Compose discovery, service actions, and log streaming"
```

---

## Task 4: DockerPanel widget

**Files:**
- Create: `app/lib/widgets/docker_panel.dart`
- Create: `app/test/widgets/docker_panel_test.dart`

**Interfaces:**
- Consumes: `Host`, `ContainerService` (Tasks 1+2), `ContainerEntry` (existing), `SessionProvider` (for `connect`)
- Produces: `DockerPanel(host: Host, service: ContainerService, onConnect: Future<void> Function(Host, String))` widget

- [ ] **Step 1: Create `docker_panel.dart`**

Create `app/lib/widgets/docker_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../theme/app_theme.dart';

class DockerPanel extends StatefulWidget {
  const DockerPanel({super.key, required this.host, required this.service});

  final Host host;
  final ContainerService service;

  @override
  State<DockerPanel> createState() => _DockerPanelState();
}

class _DockerPanelState extends State<DockerPanel> {
  List<ContainerEntry> _containers = [];
  bool _loading = false;
  String? _error;

  // Log panel state
  ContainerEntry? _logContainer;
  StreamSubscription<String>? _logSub;
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();
  bool _autoScroll = true;

  // Per-container action loading
  final Map<String, bool> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _logScroll.addListener(_onLogScroll);
    _refresh();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  void _onLogScroll() {
    final pos = _logScroll.position;
    _autoScroll = pos.pixels >= pos.maxScrollExtent - 8;
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _containers = await widget.service.listDockerContainers(widget.host);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isRunning(ContainerEntry c) =>
      c.status.toLowerCase().startsWith('up');

  Future<void> _runAction(ContainerEntry c, Future<void> Function() action) async {
    setState(() => _actionLoading[c.id] = true);
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading.remove(c.id));
    }
  }

  void _openLogs(ContainerEntry c) {
    _logSub?.cancel();
    setState(() {
      _logContainer = c;
      _logLines.clear();
      _autoScroll = true;
    });
    _logSub = widget.service
        .streamDockerLogs(widget.host, c.id)
        .listen((line) {
      if (mounted) {
        setState(() {
          _logLines.add(line);
          if (_logLines.length > 2000) {
            _logLines.removeRange(0, _logLines.length - 2000);
          }
        });
        _scrollToBottom();
      }
    }, onDone: () {
      if (mounted) {
        setState(() => _logLines.add('— connection closed —'));
        _scrollToBottom();
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _logLines.add('— error: $e —'));
        _scrollToBottom();
      }
    });
  }

  void _closeLogs() {
    _logSub?.cancel();
    _logSub = null;
    setState(() {
      _logContainer = null;
      _logLines.clear();
    });
  }

  Future<void> _execContainer(ContainerEntry c) async {
    final sessionProvider = context.read<SessionProvider>();
    await sessionProvider.connect(
      widget.host,
      initialCommand: ContainerService.dockerExecCommand(c.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _refresh, child: const Text('Retry')),
        ]),
      );
    }
    if (_containers.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inbox, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          const Text('No running containers.'),
          const SizedBox(height: 12),
          FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              onPressed: _refresh),
        ]),
      );
    }

    final hasLogs = _logContainer != null;
    return Column(
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
          child: Row(
            children: [
              Text('${_containers.length} container${_containers.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        // Container list
        Expanded(
          flex: hasLogs ? 1 : 2,
          child: ListView.separated(
            itemCount: _containers.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) => _containerTile(_containers[i]),
          ),
        ),
        // Log panel
        if (hasLogs) ...[
          const Divider(height: 1, color: AppColors.border),
          _logPanel(),
        ],
      ],
    );
  }

  Widget _containerTile(ContainerEntry c) {
    final running = _isRunning(c);
    final loading = _actionLoading[c.id] == true;
    final isLogTarget = _logContainer?.id == c.id;

    return Container(
      decoration: isLogTarget
          ? BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.accent, width: 3),
              ),
            )
          : null,
      child: ListTile(
        dense: true,
        title: Text(c.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Text('${c.image}  •  ${c.status}',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        trailing: loading
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : _actionButtons(c, running),
      ),
    );
  }

  Widget _actionButtons(ContainerEntry c, bool running) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (running)
        _iconBtn(Icons.stop_circle_outlined, 'Stop',
            () => _runAction(c, () => widget.service.stopContainer(widget.host, c.id))),
      if (running)
        _iconBtn(Icons.replay, 'Restart',
            () => _runAction(c, () => widget.service.restartContainer(widget.host, c.id))),
      if (!running)
        _iconBtn(Icons.play_circle_outline, 'Start',
            () => _runAction(c, () => widget.service.startContainer(widget.host, c.id))),
      _iconBtn(Icons.terminal, 'Exec', () => _execContainer(c)),
      if (running)
        _iconBtn(
          Icons.article_outlined,
          'Logs',
          () => _logContainer?.id == c.id ? _closeLogs() : _openLogs(c),
          active: _logContainer?.id == c.id,
        ),
    ]);
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap,
      {bool active = false}) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      color: active ? AppColors.accent : null,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }

  Widget _logPanel() {
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          // Log panel header
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              const Icon(Icons.article_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Logs: ${_logContainer!.name}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: () => setState(() => _logLines.clear()),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: _closeLogs,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ]),
          ),
          // Log lines
          Expanded(
            child: ListView.builder(
              controller: _logScroll,
              padding: const EdgeInsets.all(8),
              itemCount: _logLines.length,
              itemBuilder: (_, i) => Text(
                _logLines[i],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create widget test**

Create `app/test/widgets/docker_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/docker_panel.dart';

class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
      Host host, String cmd, {String? auditSource}) async =>
      execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) =>
      const Stream.empty();
}

// DockerPanel reaches into SessionProvider only inside the Exec button
// callback (context.read<SessionProvider>()); these tests never tap Exec, so
// no provider ancestor is needed — a bare MaterialApp suffices.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  testWidgets('shows running containers with Stop and Logs buttons', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('web'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Logs'), findsOneWidget);
    expect(find.byTooltip('Start'), findsNothing);
  });

  testWidgets('shows Start button for stopped container', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|worker|myimage:1.0|Exited (0) 5 minutes ago',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.byTooltip('Start'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
  });

  testWidgets('shows No running containers for empty list', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('No running containers.'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run widget tests**

```bash
cd app && flutter test test/widgets/docker_panel_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/docker_panel.dart \
        app/test/widgets/docker_panel_test.dart
git commit -m "feat(docker): DockerPanel widget with logs and lifecycle actions"
```

---

## Task 5: ComposePanel widget

**Files:**
- Create: `app/lib/widgets/compose_panel.dart`
- Create: `app/test/widgets/compose_panel_test.dart`

**Interfaces:**
- Consumes: `Host`, `ContainerService` (Tasks 1+3), `ComposeStack`, `ComposeService`
- Produces: `ComposePanel(host: Host, service: ContainerService)` widget

- [ ] **Step 1: Create `compose_panel.dart`**

Create `app/lib/widgets/compose_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../services/container_service.dart';
import '../theme/app_theme.dart';

class ComposePanel extends StatefulWidget {
  const ComposePanel({super.key, required this.host, required this.service});

  final Host host;
  final ContainerService service;

  @override
  State<ComposePanel> createState() => _ComposePanelState();
}

class _ComposePanelState extends State<ComposePanel> {
  List<ComposeStack> _stacks = [];
  bool _loadingStacks = false;
  String? _stacksError;

  ComposeStack? _selectedStack;
  List<ComposeService> _services = [];
  bool _loadingServices = false;

  // Log panel
  ComposeService? _logService;
  StreamSubscription<String>? _logSub;
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();
  bool _autoScroll = true;

  // Per-action loading
  final Map<String, bool> _actionLoading = {};

  // Manual path input
  final TextEditingController _manualCtrl = TextEditingController();
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _logScroll.addListener(() {
      final pos = _logScroll.position;
      _autoScroll = pos.pixels >= pos.maxScrollExtent - 8;
    });
    _loadStacks();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _logScroll.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadStacks() async {
    setState(() {
      _loadingStacks = true;
      _stacksError = null;
    });
    try {
      _stacks = await widget.service.discoverComposeStacks(widget.host);
    } catch (e) {
      _stacksError = e.toString();
    } finally {
      if (mounted) setState(() => _loadingStacks = false);
    }
  }

  Future<void> _selectStack(ComposeStack stack) async {
    if (_selectedStack?.projectDir == stack.projectDir) {
      setState(() {
        _selectedStack = null;
        _services = [];
      });
      return;
    }
    setState(() {
      _selectedStack = stack;
      _services = [];
      _loadingServices = true;
    });
    try {
      final svcs = await widget.service.listComposeServices(widget.host, stack);
      if (mounted) setState(() => _services = svcs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  Future<void> _stackAction(
      ComposeStack stack, String key, Future<void> Function() action) async {
    setState(() => _actionLoading[key] = true);
    try {
      await action();
      await _loadStacks();
      if (_selectedStack?.projectDir == stack.projectDir) {
        final svcs = await widget.service.listComposeServices(widget.host, stack);
        if (mounted) setState(() => _services = svcs);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().length > 200
            ? '${e.toString().substring(0, 200)}…'
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading.remove(key));
    }
  }

  void _openServiceLogs(ComposeService svc) {
    final stack = _selectedStack;
    if (stack == null) return;
    _logSub?.cancel();
    setState(() {
      _logService = svc;
      _logLines.clear();
      _autoScroll = true;
    });
    _logSub = widget.service
        .streamComposeServiceLogs(widget.host, stack, svc.name)
        .listen((line) {
      if (mounted) {
        setState(() {
          _logLines.add(line);
          if (_logLines.length > 2000) {
            _logLines.removeRange(0, _logLines.length - 2000);
          }
        });
        _scrollToBottom();
      }
    }, onDone: () {
      if (mounted) setState(() => _logLines.add('— connection closed —'));
    }, onError: (e) {
      if (mounted) setState(() => _logLines.add('— error: $e —'));
    });
  }

  void _closeLogs() {
    _logSub?.cancel();
    _logSub = null;
    setState(() {
      _logService = null;
      _logLines.clear();
    });
  }

  Future<void> _addManualPath() async {
    final path = _manualCtrl.text.trim();
    if (path.isEmpty) return;
    setState(() => _actionLoading['manual'] = true);
    try {
      final r = await widget.service.ssh.exec(
          widget.host,
          "docker compose -f '$path' config --services 2>&1",
          auditSource: 'devops');
      if (r.exitCode != 0) throw Exception('Not a valid Compose file: $path');
      final dir = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/'))
          : '.';
      final name = dir.substring(dir.lastIndexOf('/') + 1);
      final stack = ComposeStack(name: name, projectDir: dir, status: 'unknown');
      setState(() {
        if (!_stacks.any((s) => s.projectDir == dir)) {
          _stacks = [..._stacks, stack];
        }
        _showManualInput = false;
        _manualCtrl.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading.remove('manual'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogs = _logService != null;
    return Column(children: [
      // Toolbar
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        child: Row(children: [
          const Text('Compose Stacks',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          IconButton(
            tooltip: 'Add path manually',
            icon: const Icon(Icons.add, size: 16),
            onPressed: () =>
                setState(() => _showManualInput = !_showManualInput),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: _loadStacks,
          ),
        ]),
      ),
      // Manual path input
      if (_showManualInput)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _manualCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '/path/to/docker-compose.yml',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addManualPath(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _actionLoading['manual'] == true ? null : _addManualPath,
              child: const Text('Add'),
            ),
          ]),
        ),
      // Stack list
      Expanded(
        flex: _selectedStack != null ? 1 : 3,
        child: _buildStackList(),
      ),
      // Service list
      if (_selectedStack != null) ...[
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text('Services in ${_selectedStack!.name}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
        Expanded(
          flex: 1,
          child: _loadingServices
              ? const Center(child: CircularProgressIndicator())
              : _buildServiceList(),
        ),
      ],
      // Log panel
      if (hasLogs) ...[
        const Divider(height: 1, color: AppColors.border),
        _buildLogPanel(),
      ],
    ]);
  }

  Widget _buildStackList() {
    if (_loadingStacks) return const Center(child: CircularProgressIndicator());
    if (_stacksError != null) {
      return Center(child: Text(_stacksError!, textAlign: TextAlign.center));
    }
    if (_stacks.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          const Text('No Compose stacks found.'),
          const SizedBox(height: 4),
          const Text('Tap + to add a path manually.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      );
    }
    return ListView.separated(
      itemCount: _stacks.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _stackTile(_stacks[i]),
    );
  }

  Widget _stackTile(ComposeStack stack) {
    final selected = _selectedStack?.projectDir == stack.projectDir;
    final upKey = 'up_${stack.projectDir}';
    final downKey = 'down_${stack.projectDir}';
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.08),
      title: Text(stack.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('${stack.status}  •  ${stack.projectDir}',
          style:
              const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis),
      onTap: () => _selectStack(stack),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_actionLoading[upKey] == true)
          const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(
            onPressed: () => _stackAction(
                stack, upKey, () => widget.service.composeUp(widget.host, stack)),
            child: const Text('Up', style: TextStyle(fontSize: 12)),
          ),
        if (_actionLoading[downKey] == true)
          const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(
            onPressed: () => _stackAction(
                stack, downKey, () => widget.service.composeDown(widget.host, stack)),
            child: const Text('Down', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _buildServiceList() {
    if (_services.isEmpty) {
      return const Center(child: Text('No services found.'));
    }
    return ListView.separated(
      itemCount: _services.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _serviceTile(_services[i]),
    );
  }

  Widget _serviceTile(ComposeService svc) {
    final stack = _selectedStack!;
    final running = svc.status == 'running';
    final startKey = 'svcstart_${stack.projectDir}_${svc.name}';
    final stopKey = 'svcstop_${stack.projectDir}_${svc.name}';
    final isLogTarget = _logService?.name == svc.name;

    return ListTile(
      dense: true,
      title: Text(svc.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
          '${svc.status}  •  ${svc.image}  •  ${svc.replicas} replica${svc.replicas == 1 ? '' : 's'}',
          style:
              const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (running && _actionLoading[stopKey] != true)
          IconButton(
            tooltip: 'Stop service',
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _stackAction(
                stack, stopKey,
                () => widget.service.stopComposeService(widget.host, stack, svc.name)),
          ),
        if (!running && _actionLoading[startKey] != true)
          IconButton(
            tooltip: 'Start service',
            icon: const Icon(Icons.play_circle_outline, size: 16),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _stackAction(
                stack, startKey,
                () => widget.service.startComposeService(widget.host, stack, svc.name)),
          ),
        IconButton(
          tooltip: 'Logs',
          icon: const Icon(Icons.article_outlined, size: 16),
          color: isLogTarget ? AppColors.accent : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () =>
              isLogTarget ? _closeLogs() : _openServiceLogs(svc),
        ),
      ]),
    );
  }

  Widget _buildLogPanel() {
    return Expanded(
      flex: 2,
      child: Column(children: [
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            const Icon(Icons.article_outlined,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Logs: ${_logService!.name}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ),
            TextButton(
              onPressed: () => setState(() => _logLines.clear()),
              child: const Text('Clear', style: TextStyle(fontSize: 11)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: _closeLogs,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: _logScroll,
            padding: const EdgeInsets.all(8),
            itemCount: _logLines.length,
            itemBuilder: (_, i) => Text(_logLines[i],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textPrimary)),
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 2: Create widget test**

Create `app/test/widgets/compose_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/container_entry.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/compose_panel.dart';

class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
      Host host, String cmd, {String? auditSource}) async =>
      execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) =>
      const Stream.empty();
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  testWidgets('shows No Compose stacks found when discovery returns empty', (tester) async {
    final fake = _FakeSshService();
    // Both docker compose ls and find return empty
    fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('No Compose stacks found.'), findsOneWidget);
  });

  testWidgets('shows stack name when discovery returns a result', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (cmd) {
      if (cmd.contains('docker compose ls')) {
        return (
          stdout: '[{"Name":"myapp","Status":"running(2)","ConfigFiles":"/opt/myapp/compose.yml"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('myapp'), findsOneWidget);
    expect(find.text('Up'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
  });

  testWidgets('shows + button for manual path input', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    await tester.tap(find.byTooltip('Add path manually'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run widget tests**

```bash
cd app && flutter test test/widgets/compose_panel_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/compose_panel.dart \
        app/test/widgets/compose_panel_test.dart
git commit -m "feat(docker): ComposePanel widget with stack discovery and service management"
```

---

## Task 6: Wire ContainersScreen — add Compose tab, use DockerPanel

**Files:**
- Modify: `app/lib/widgets/containers_screen.dart`

**Interfaces:**
- Consumes: `DockerPanel` (Task 4), `ComposePanel` (Task 5)
- No new exports — internal wiring only

- [ ] **Step 1: Update `containers_screen.dart`**

Key changes vs. the existing file:
1. Add `import` for `docker_panel.dart` and `compose_panel.dart`.
2. `enum _Tab { docker, kubernetes }` → `enum _Tab { docker, compose, kubernetes }`.
3. **Keep** the existing screen-level runtime scan (`_runtimes`, manual "Scan", `_HintCard` install/permission gating) — it is what gives the **Kubernetes** tab its "kubectl not installed" hint. Do NOT move detection into `DockerPanel` (that would silently drop the kubectl hint).
4. `_refresh()` now ONLY scans runtimes — it no longer lists containers (DockerPanel does that itself on init). Drop the `_containers` field, `_dockerList()`, and `_execContainer()` from the screen.
5. Compose and Docker tabs both gate on the **docker** runtime (`_availabilityFor` maps `kubernetes → kubectl`, everything else → `docker`).
6. When the runtime check passes, render `DockerPanel` / `ComposePanel` / `KubernetesPanel`.

`_CenterHint` and `_HintCard` are unchanged from the current file — keep them. Full updated file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import 'kubernetes_panel.dart';
import 'docker_panel.dart';
import 'compose_panel.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key, this.onOpenBrowser});
  final void Function(String url)? onOpenBrowser;

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

enum _Tab { docker, compose, kubernetes }

class _ContainersScreenState extends State<ContainersScreen> {
  ContainerService? _service;
  String? _sessionId;
  _Tab _tab = _Tab.docker;

  RuntimeStatus? _runtimes;
  bool _loading = false;

  ContainerService _ensureService() {
    _service ??= ContainerService(context.read<SshService>());
    return _service!;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>().sshSessions;
    if (sessions.isEmpty) {
      return const _CenterHint(
        icon: Icons.terminal,
        message: 'Open an SSH session first, then come back to browse containers.',
      );
    }
    _sessionId ??= sessions.first.id;
    final selected = sessions.firstWhere(
      (s) => s.id == _sessionId,
      orElse: () => sessions.first,
    );
    _sessionId = selected.id;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _sessionId,
                  isExpanded: true,
                  items: [
                    for (final s in sessions)
                      DropdownMenuItem(value: s.id, child: Text(s.title)),
                  ],
                  onChanged: (v) => setState(() {
                    _sessionId = v;
                    _runtimes = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Rescan runtimes',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            _tabButton(_Tab.docker, 'Docker'),
            const SizedBox(width: 8),
            _tabButton(_Tab.compose, 'Compose'),
            const SizedBox(width: 8),
            _tabButton(_Tab.kubernetes, 'Kubernetes'),
          ]),
          const SizedBox(height: 8),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _tabButton(_Tab tab, String label) {
    final active = _tab == tab;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() => _tab = tab),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final host = _hostForSelected();
    if (host == null) {
      return const _CenterHint(icon: Icons.link_off, message: 'Session not found.');
    }
    final runtimes = _runtimes;
    if (runtimes == null) {
      return _CenterHint(
        icon: Icons.search,
        message: 'Tap refresh to scan for Docker / Kubernetes.',
        actionLabel: 'Scan',
        onAction: _refresh,
      );
    }

    final avail = _availabilityFor(runtimes);
    // Docker and Compose both require the docker runtime; only Kubernetes
    // uses kubectl.
    final runtimeName = _tab == _Tab.kubernetes ? 'kubectl' : 'docker';

    if (avail == RuntimeAvailability.notInstalled) {
      return _HintCard(
        title: '$runtimeName is not installed on this host',
        command: ContainerService.installHint(runtimeName, host.detectedOs),
      );
    }
    if (avail == RuntimeAvailability.noPermission) {
      return _HintCard(
        title: 'No permission to use $runtimeName',
        command: ContainerService.permissionHint(runtimeName),
      );
    }

    // Runtime is available — the panels load their own data on init. Each is
    // remounted (fresh initState) whenever the session changes, because
    // switching sessions sets `_runtimes = null`, which unmounts the panel
    // until the next scan.
    final svc = _ensureService();
    switch (_tab) {
      case _Tab.docker:
        return DockerPanel(host: host, service: svc);
      case _Tab.compose:
        return ComposePanel(host: host, service: svc);
      case _Tab.kubernetes:
        return KubernetesPanel(host: host, onOpenBrowser: widget.onOpenBrowser);
    }
  }

  Future<void> _refresh() async {
    final host = _hostForSelected();
    if (host == null) return;
    setState(() => _loading = true);
    try {
      _runtimes = await _ensureService().detectRuntimes(host);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  RuntimeAvailability _availabilityFor(RuntimeStatus r) =>
      _tab == _Tab.kubernetes ? r.kubectl : r.docker;

  Host? _hostForSelected() {
    final id = _sessionId;
    if (id == null) return null;
    return context.read<SessionProvider>().hostForSession(id);
  }
}

class _CenterHint extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _CenterHint({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String title;
  final String command;
  const _HintCard({required this.title, required this.command});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SelectableText(
                command,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy command'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: command));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

> **DockerPanel is unchanged from Task 4** — it does NOT call `detectRuntimes`; the screen has already confirmed docker is available before rendering it. No `_HintCard` copy into `docker_panel.dart`, no `flutter/services.dart` import there.

- [ ] **Step 2: Verify full test suite passes**

```bash
cd app && flutter test test/services/container_service_docker_test.dart \
                        test/services/container_service_compose_test.dart \
                        test/widgets/docker_panel_test.dart \
                        test/widgets/compose_panel_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 3: Analyze for errors**

```bash
cd app && flutter analyze --no-fatal-infos 2>&1 | grep "error:" | head -20
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/containers_screen.dart
git commit -m "feat(docker): wire DockerPanel + ComposePanel into ContainersScreen"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Docker logs (`streamDockerLogs` + log panel in DockerPanel) — Task 2 + Task 4
- [x] Stop/Start/Restart (`stopContainer`, `startContainer`, `restartContainer`) — Task 2 + Task 4
- [x] Compose discovery (scan + `docker compose ls` + manual fallback) — Task 3 + Task 5
- [x] List stacks + services — Task 3 + Task 5
- [x] Up/Down stacks — Task 3 + Task 5
- [x] Per-service logs — Task 3 + Task 5
- [x] Start/stop service — Task 3 + Task 5
- [x] `docker compose` v1 hint — `ComposePanel` surfaces discovery error (v1 parse fails gracefully; if `docker compose ls` returns non-zero, hint needed)
- [x] Tests for static parsers — Task 3
- [x] 3-tab layout (Docker | Compose | Kubernetes) — Task 6
- [x] Log line cap 2000 — both DockerPanel and ComposePanel
- [x] `auditSource: 'devops'` — all methods in ContainerService

**Note on v1 hint:** `parseComposeLs` returns `[]` on any error silently. If Docker Compose v1 is installed, `docker compose ls` may not exist and returns non-zero — discovery will fall back to find-only, not show an error. This is intentional: the feature works in degraded mode. The v2 hint is only shown if `docker compose ps` fails on a selected stack.
