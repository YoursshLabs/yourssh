# Docker / Kubernetes Exec Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** List Docker containers and Kubernetes pods on a remote host over an existing SSH session, and exec into them in a fresh terminal tab — surfaced as a "Containers" sub-screen in the DevOps plugin.

**Architecture:** A pure-Dart `ContainerService` runs `docker ps` / `kubectl get pods` via the existing `SshService.exec(host, cmd)` and parses the output with stateless functions (unit-testable without SSH). An app-side `ContainersScreen` (it needs `SessionProvider`/`SshService`) is injected into the DevOps hub via a new `DevOpsPluginConfig.containersScreen` slot, matching the existing `networkToolsScreen` pattern. Exec opens a new session tab by threading an `initialCommand` through `SessionProvider.connect` → `openShell`, reusing the same `shell.write(...)` mechanism the tmux auto-attach already uses.

**Tech Stack:** Flutter, Dart, `provider`, `dartssh2` (local fork), `flutter_test`.

---

## File Structure

- Create: `app/lib/models/container_entry.dart` — `ContainerEntry`, `PodEntry`, `RuntimeAvailability`, `RuntimeStatus`.
- Create: `app/lib/services/container_service.dart` — listing + pure parsers + runtime classification + install-hint helper.
- Create: `app/lib/widgets/containers_screen.dart` — the UI.
- Create: `app/test/services/container_service_test.dart` — parser/classifier/hint tests.
- Modify: `app/lib/models/ssh_session.dart` — add `initialCommand`.
- Modify: `app/lib/services/ssh_service.dart` — `openShell` runs `initialCommand`.
- Modify: `app/lib/providers/session_provider.dart` — `connect`/`_doConnect` thread `initialCommand`.
- Modify: `packages/yourssh_devops/lib/src/devops_plugin_config.dart` — add `containersScreen`.
- Modify: `packages/yourssh_devops/lib/src/screens/devops_hub_screen.dart` — add `containers` tool.
- Modify: `app/lib/plugins/plugin_registry.dart` — register `ContainersScreen`.

---

## Task 1: Models + Docker `ps` parser

**Files:**
- Create: `app/lib/models/container_entry.dart`
- Create: `app/lib/services/container_service.dart`
- Test: `app/test/services/container_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/services/container_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/container_entry.dart';
import 'package:yourssh/services/container_service.dart';

void main() {
  group('parseDockerPs', () {
    test('parses pipe-delimited docker ps output', () {
      const out =
          'a1b2c3|web|nginx:latest|Up 2 hours\n'
          'd4e5f6|db|postgres:16|Up 5 minutes (healthy)\n';
      final list = ContainerService.parseDockerPs(out);
      expect(list.length, 2);
      expect(list[0].id, 'a1b2c3');
      expect(list[0].name, 'web');
      expect(list[0].image, 'nginx:latest');
      expect(list[0].status, 'Up 2 hours');
      expect(list[1].name, 'db');
    });

    test('ignores blank and malformed lines', () {
      const out = 'a1|web|nginx|Up\n\nbadline\n';
      final list = ContainerService.parseDockerPs(out);
      expect(list.length, 1);
      expect(list.single.id, 'a1');
    });

    test('empty output yields empty list', () {
      expect(ContainerService.parseDockerPs(''), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/container_service_test.dart`
Expected: FAIL — `container_entry.dart` / `container_service.dart` don't exist (compile error).

- [ ] **Step 3: Create the models**

Create `app/lib/models/container_entry.dart`:

```dart
/// One running Docker container (subset of `docker ps`).
class ContainerEntry {
  final String id;
  final String name;
  final String image;
  final String status;

  const ContainerEntry({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
  });
}

/// One Kubernetes pod (subset of `kubectl get pods`).
class PodEntry {
  final String name;
  final String namespace;
  final String ready;
  final String status;
  final List<String> containers;

  const PodEntry({
    required this.name,
    required this.namespace,
    required this.ready,
    required this.status,
    this.containers = const [],
  });
}

enum RuntimeAvailability { available, notInstalled, noPermission }

class RuntimeStatus {
  final RuntimeAvailability docker;
  final RuntimeAvailability kubectl;

  const RuntimeStatus({required this.docker, required this.kubectl});
}
```

- [ ] **Step 4: Create the service with the Docker parser**

Create `app/lib/services/container_service.dart`:

```dart
import '../models/container_entry.dart';
import 'ssh_service.dart';
import '../models/host.dart';

/// Lists Docker containers / Kubernetes pods on a remote host and detects
/// which container runtimes are available. Parsing is done by stateless
/// functions so it can be unit-tested without an SSH connection.
class ContainerService {
  final SshService ssh;
  ContainerService(this.ssh);

  // ── Docker ────────────────────────────────────────────
  static const _dockerFormat = '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}';

  Future<List<ContainerEntry>> listDockerContainers(Host host) async {
    final r = await ssh.exec(host, "docker ps --format '$_dockerFormat'");
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker ps failed' : r.stderr.trim());
    }
    return parseDockerPs(r.stdout);
  }

  static List<ContainerEntry> parseDockerPs(String stdout) {
    final out = <ContainerEntry>[];
    for (final line in stdout.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final parts = t.split('|');
      if (parts.length < 4) continue;
      out.add(ContainerEntry(
        id: parts[0],
        name: parts[1],
        image: parts[2],
        status: parts.sublist(3).join('|'),
      ));
    }
    return out;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/services/container_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/container_entry.dart app/lib/services/container_service.dart app/test/services/container_service_test.dart
git commit -m "feat(containers): models + docker ps parser"
```

---

## Task 2: Kubernetes pod + container-name parsers

**Files:**
- Modify: `app/lib/services/container_service.dart`
- Test: `app/test/services/container_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add these groups to `app/test/services/container_service_test.dart` (inside `main()`):

```dart
  group('parsePods', () {
    test('parses single-namespace kubectl get pods', () {
      const out =
          'NAME       READY   STATUS    RESTARTS   AGE\n'
          'web-0      1/1     Running   0          2d\n'
          'db-0       0/1     Pending   0          5m\n';
      final list = ContainerService.parsePods(out, namespace: 'prod');
      expect(list.length, 2);
      expect(list[0].name, 'web-0');
      expect(list[0].namespace, 'prod');
      expect(list[0].ready, '1/1');
      expect(list[0].status, 'Running');
      expect(list[1].status, 'Pending');
    });

    test('parses all-namespaces output (NAMESPACE column first)', () {
      const out =
          'NAMESPACE   NAME    READY   STATUS    RESTARTS   AGE\n'
          'kube-system   coredns   1/1   Running   1   10d\n';
      final list = ContainerService.parsePods(out, allNamespaces: true);
      expect(list.single.namespace, 'kube-system');
      expect(list.single.name, 'coredns');
      expect(list.single.status, 'Running');
    });

    test('empty / header-only output yields empty list', () {
      expect(ContainerService.parsePods('', namespace: 'x'), isEmpty);
      expect(ContainerService.parsePods('NAME READY STATUS', namespace: 'x'), isEmpty);
    });
  });

  group('parseContainerNames', () {
    test('splits whitespace-separated names', () {
      expect(ContainerService.parseContainerNames('app sidecar  \n'),
          ['app', 'sidecar']);
    });
    test('empty output yields empty list', () {
      expect(ContainerService.parseContainerNames('  \n'), isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/container_service_test.dart`
Expected: FAIL — `parsePods` / `parseContainerNames` not defined.

- [ ] **Step 3: Implement the parsers + listing methods**

Add to the `ContainerService` class in `app/lib/services/container_service.dart`:

```dart
  // ── Kubernetes ────────────────────────────────────────
  Future<List<PodEntry>> listPods(
    Host host, {
    String namespace = 'default',
    bool allNamespaces = false,
  }) async {
    final scope = allNamespaces ? '-A' : '-n $namespace';
    final r = await ssh.exec(host, 'kubectl get pods $scope');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'kubectl failed' : r.stderr.trim());
    }
    return parsePods(r.stdout, namespace: namespace, allNamespaces: allNamespaces);
  }

  Future<List<String>> podContainers(Host host, String pod, String namespace) async {
    final r = await ssh.exec(host,
        "kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].name}'");
    if (r.exitCode != 0) return const [];
    return parseContainerNames(r.stdout);
  }

  static List<PodEntry> parsePods(
    String stdout, {
    String namespace = 'default',
    bool allNamespaces = false,
  }) {
    final lines = stdout.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];
    final out = <PodEntry>[];
    // Skip the header row (starts with NAME or NAMESPACE).
    for (final line in lines) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.isEmpty) continue;
      if (cols.first == 'NAME' || cols.first == 'NAMESPACE') continue;
      if (allNamespaces) {
        if (cols.length < 4) continue;
        out.add(PodEntry(
          namespace: cols[0],
          name: cols[1],
          ready: cols[2],
          status: cols[3],
        ));
      } else {
        if (cols.length < 3) continue;
        out.add(PodEntry(
          namespace: namespace,
          name: cols[0],
          ready: cols[1],
          status: cols[2],
        ));
      }
    }
    return out;
  }

  static List<String> parseContainerNames(String stdout) =>
      stdout.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/container_service_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/container_service.dart app/test/services/container_service_test.dart
git commit -m "feat(containers): kubectl pod + container-name parsers"
```

---

## Task 3: Runtime detection + install-hint helper

**Files:**
- Modify: `app/lib/services/container_service.dart`
- Test: `app/test/services/container_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `app/test/services/container_service_test.dart` (inside `main()`):

```dart
  group('classifyRuntime', () {
    test('missing command -> notInstalled', () {
      expect(
        ContainerService.classifyRuntime(commandExists: false, psExitCode: 127, psStderr: ''),
        RuntimeAvailability.notInstalled,
      );
    });
    test('present + ps ok -> available', () {
      expect(
        ContainerService.classifyRuntime(commandExists: true, psExitCode: 0, psStderr: ''),
        RuntimeAvailability.available,
      );
    });
    test('present + permission denied -> noPermission', () {
      expect(
        ContainerService.classifyRuntime(
            commandExists: true, psExitCode: 1, psStderr: 'permission denied while trying to connect to the Docker daemon socket'),
        RuntimeAvailability.noPermission,
      );
    });
    test('present + other error -> available (let listing surface it)', () {
      expect(
        ContainerService.classifyRuntime(commandExists: true, psExitCode: 1, psStderr: 'Cannot connect: timeout'),
        RuntimeAvailability.available,
      );
    });
  });

  group('installHint', () {
    test('docker on ubuntu suggests get.docker.com', () {
      final h = ContainerService.installHint('docker', 'Ubuntu 22.04');
      expect(h, contains('get.docker.com'));
    });
    test('docker noPermission suggests usermod group', () {
      final h = ContainerService.permissionHint('docker');
      expect(h, contains('usermod -aG docker'));
    });
    test('kubectl hint is non-empty for unknown os', () {
      expect(ContainerService.installHint('kubectl', null), isNotEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/container_service_test.dart`
Expected: FAIL — `classifyRuntime` / `installHint` / `permissionHint` not defined.

- [ ] **Step 3: Implement detection + hints**

Add to the `ContainerService` class in `app/lib/services/container_service.dart`:

```dart
  // ── Runtime detection ─────────────────────────────────
  Future<RuntimeStatus> detectRuntimes(Host host) async {
    return RuntimeStatus(
      docker: await _detectOne(host, 'docker', 'docker ps'),
      kubectl: await _detectOne(host, 'kubectl', 'kubectl version --client'),
    );
  }

  Future<RuntimeAvailability> _detectOne(Host host, String cmd, String probe) async {
    final exists = await ssh.exec(host, 'command -v $cmd');
    if (exists.exitCode != 0) return RuntimeAvailability.notInstalled;
    final p = await ssh.exec(host, probe);
    return classifyRuntime(
      commandExists: true,
      psExitCode: p.exitCode,
      psStderr: p.stderr,
    );
  }

  static RuntimeAvailability classifyRuntime({
    required bool commandExists,
    required int psExitCode,
    required String psStderr,
  }) {
    if (!commandExists) return RuntimeAvailability.notInstalled;
    if (psExitCode == 0) return RuntimeAvailability.available;
    if (psStderr.toLowerCase().contains('permission denied')) {
      return RuntimeAvailability.noPermission;
    }
    return RuntimeAvailability.available;
  }

  // ── Install / fix hints ───────────────────────────────
  static String installHint(String runtime, String? os) {
    final isDebian = (os ?? '').toLowerCase().contains(RegExp(r'ubuntu|debian'));
    if (runtime == 'docker') {
      return isDebian
          ? 'curl -fsSL https://get.docker.com | sh'
          : 'See https://docs.docker.com/engine/install/';
    }
    // kubectl
    return isDebian
        ? 'sudo apt-get update && sudo apt-get install -y kubectl'
        : 'curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/';
  }

  static String permissionHint(String runtime) {
    if (runtime == 'docker') {
      return 'sudo usermod -aG docker \$USER   # then log out and back in';
    }
    return 'Check your kubeconfig / RBAC permissions.';
  }
```

Note: `os.toLowerCase().contains(RegExp(...))` — `String.contains` accepts a `Pattern`, so a `RegExp` is valid.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/container_service_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/container_service.dart app/test/services/container_service_test.dart
git commit -m "feat(containers): runtime detection + install hints"
```

---

## Task 4: Thread `initialCommand` through session open

**Files:**
- Modify: `app/lib/models/ssh_session.dart`
- Modify: `app/lib/services/ssh_service.dart:298` (`openShell`)
- Modify: `app/lib/providers/session_provider.dart:58,67,102` (`connect`/`_doConnect`)
- Test: `app/test/models/ssh_session_initial_command_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/models/ssh_session_initial_command_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

void main() {
  test('SshSession stores an optional initialCommand', () {
    final host = Host(host: '1.2.3.4', port: 22, username: 'root');
    final s = SshSession(host: host, initialCommand: 'docker exec -it abc sh');
    expect(s.initialCommand, 'docker exec -it abc sh');
    expect(SshSession(host: host).initialCommand, isNull);
  });
}
```

(If `Host`'s required constructor args differ, match `app/lib/models/host.dart`; `host`, `port`, `username` are the core fields.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/ssh_session_initial_command_test.dart`
Expected: FAIL — `initialCommand` named param not defined.

- [ ] **Step 3: Add `initialCommand` to `SshSession`**

In `app/lib/models/ssh_session.dart`, add the field and constructor param:

```dart
  final String? initialCommand;
```

Add to the constructor parameter list (after `connectedAt`):

```dart
    this.initialCommand,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/ssh_session_initial_command_test.dart`
Expected: PASS.

- [ ] **Step 5: Run `initialCommand` in `openShell`**

In `app/lib/services/ssh_service.dart`, `openShell` (around line 323), replace the tmux block so the initial command also runs:

```dart
    if (useTmux) {
      shell.write(Uint8List.fromList('tmux new-session -A -s yourssh\n'.codeUnits));
    }
    if (session.initialCommand != null && session.initialCommand!.isNotEmpty) {
      shell.write(Uint8List.fromList('${session.initialCommand!}\n'.codeUnits));
    }
```

- [ ] **Step 6: Thread `initialCommand` through `SessionProvider.connect`**

In `app/lib/providers/session_provider.dart`:

Change `connect` (line 58):

```dart
  Future<void> connect(Host host, {String? initialCommand}) async {
    final session = SshSession(host: host, initialCommand: initialCommand);
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();

    await _doConnect(session, host, attempt: 1);
  }
```

(`_doConnect` already calls `_ssh.openShell(session, ...)` at line 102 — since `initialCommand` now lives on `session`, `openShell` picks it up with no further change.)

- [ ] **Step 7: Verify analyze + existing session tests pass**

Run: `cd app && flutter analyze lib/models/ssh_session.dart lib/services/ssh_service.dart lib/providers/session_provider.dart && flutter test test/models/ssh_session_initial_command_test.dart`
Expected: No analyzer errors; test PASS.

- [ ] **Step 8: Commit**

```bash
git add app/lib/models/ssh_session.dart app/lib/services/ssh_service.dart app/lib/providers/session_provider.dart app/test/models/ssh_session_initial_command_test.dart
git commit -m "feat(session): support initialCommand run on shell open"
```

---

## Task 5: `ContainersScreen` UI

**Files:**
- Create: `app/lib/widgets/containers_screen.dart`

This task is UI assembly; it is verified via `flutter analyze` + manual run (Task 7), not a widget unit test (the parsing/classification logic it relies on is already covered by Tasks 1-3).

- [ ] **Step 1: Build the exec-command helpers (pure, testable)**

Add to `app/test/services/container_service_test.dart` (inside `main()`):

```dart
  group('exec commands', () {
    test('docker exec uses bash->sh fallback', () {
      final cmd = ContainerService.dockerExecCommand('abc123');
      expect(cmd, contains('docker exec -it abc123'));
      expect(cmd, contains('exec bash || exec sh'));
    });
    test('kubectl exec includes namespace and container', () {
      final cmd = ContainerService.kubectlExecCommand('web-0', 'prod', 'app');
      expect(cmd, contains('kubectl exec -it web-0'));
      expect(cmd, contains('-n prod'));
      expect(cmd, contains('-c app'));
      expect(cmd, contains('--'));
    });
    test('kubectl exec omits -c when container is null', () {
      final cmd = ContainerService.kubectlExecCommand('web-0', 'prod', null);
      expect(cmd, isNot(contains('-c ')));
    });
  });
```

Run: `cd app && flutter test test/services/container_service_test.dart` → FAIL (not defined).

Add to `ContainerService`:

```dart
  // ── Exec command builders ─────────────────────────────
  static const _shFallback =
      "sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'";

  static String dockerExecCommand(String id) =>
      'docker exec -it $id $_shFallback';

  static String kubectlExecCommand(String pod, String namespace, String? container) {
    final c = container == null ? '' : '-c $container ';
    return 'kubectl exec -it $pod -n $namespace $c-- $_shFallback';
  }
```

Run again → PASS. Commit:

```bash
git add app/lib/services/container_service.dart app/test/services/container_service_test.dart
git commit -m "feat(containers): exec command builders"
```

- [ ] **Step 2: Create the screen**

Create `app/lib/widgets/containers_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

enum _Tab { docker, kubernetes }

class _ContainersScreenState extends State<ContainersScreen> {
  ContainerService? _service;
  String? _sessionId; // active session id used as source
  _Tab _tab = _Tab.docker;

  RuntimeStatus? _runtimes;
  List<ContainerEntry> _containers = [];
  List<PodEntry> _pods = [];
  String _namespace = 'default';
  bool _allNamespaces = false;

  bool _loading = false;
  String? _error;

  ContainerService _ensureService() {
    _service ??= ContainerService(context.read<SshService>());
    return _service!;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>().sessions;
    if (sessions.isEmpty) {
      return const _CenterHint(
        icon: Icons.terminal,
        message: 'Open an SSH session first, then come back to browse containers.',
      );
    }
    // Default to the active/first session.
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
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            _tabButton(_Tab.docker, 'Docker'),
            const SizedBox(width: 8),
            _tabButton(_Tab.kubernetes, 'Kubernetes'),
          ]),
          if (_tab == _Tab.kubernetes) _namespaceControls(),
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

  Widget _namespaceControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        SizedBox(
          width: 200,
          child: TextField(
            enabled: !_allNamespaces,
            decoration: const InputDecoration(labelText: 'Namespace', isDense: true),
            controller: TextEditingController(text: _namespace)
              ..selection = TextSelection.collapsed(offset: _namespace.length),
            onSubmitted: (v) {
              _namespace = v.trim().isEmpty ? 'default' : v.trim();
              _refresh();
            },
          ),
        ),
        const SizedBox(width: 12),
        Row(children: [
          Checkbox(
            value: _allNamespaces,
            onChanged: (v) => setState(() {
              _allNamespaces = v ?? false;
              _refresh();
            }),
          ),
          const Text('All namespaces'),
        ]),
      ]),
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

    final avail = _tab == _Tab.docker ? runtimes.docker : runtimes.kubectl;
    final runtimeName = _tab == _Tab.docker ? 'docker' : 'kubectl';

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
    if (_error != null) {
      return _CenterHint(icon: Icons.error_outline, message: _error!);
    }
    return _tab == _Tab.docker ? _dockerList() : _podList();
  }

  Widget _dockerList() {
    if (_containers.isEmpty) {
      return const _CenterHint(icon: Icons.inbox, message: 'No running containers.');
    }
    return ListView.separated(
      itemCount: _containers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = _containers[i];
        return ListTile(
          title: Text(c.name),
          subtitle: Text('${c.image}  •  ${c.status}'),
          trailing: FilledButton.icon(
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Exec'),
            onPressed: () => _execContainer(c),
          ),
        );
      },
    );
  }

  Widget _podList() {
    if (_pods.isEmpty) {
      return const _CenterHint(icon: Icons.inbox, message: 'No pods.');
    }
    return ListView.separated(
      itemCount: _pods.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _pods[i];
        return ListTile(
          title: Text(p.name),
          subtitle: Text('${p.namespace}  •  ${p.ready}  •  ${p.status}'),
          trailing: FilledButton.icon(
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Exec'),
            onPressed: () => _execPod(p),
          ),
        );
      },
    );
  }

  // ── Actions ───────────────────────────────────────────
  Future<void> _refresh() async {
    final host = _hostForSelected();
    if (host == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = _ensureService();
      _runtimes = await svc.detectRuntimes(host);
      if (_tab == _Tab.docker &&
          _runtimes!.docker == RuntimeAvailability.available) {
        _containers = await svc.listDockerContainers(host);
      } else if (_tab == _Tab.kubernetes &&
          _runtimes!.kubectl == RuntimeAvailability.available) {
        _pods = await svc.listPods(host,
            namespace: _namespace, allNamespaces: _allNamespaces);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _execContainer(ContainerEntry c) async {
    final host = _hostForSelected();
    if (host == null) return;
    await context.read<SessionProvider>().connect(
          host,
          initialCommand: ContainerService.dockerExecCommand(c.id),
        );
  }

  Future<void> _execPod(PodEntry p) async {
    final host = _hostForSelected();
    if (host == null) return;
    String? container;
    final names = await _ensureService().podContainers(host, p.name, p.namespace);
    if (names.length > 1 && mounted) {
      container = await showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Select container'),
          children: [
            for (final n in names)
              SimpleDialogOption(
                child: Text(n),
                onPressed: () => Navigator.pop(context, n),
              ),
          ],
        ),
      );
      if (container == null) return; // cancelled
    } else if (names.length == 1) {
      container = names.first;
    }
    if (!mounted) return;
    await context.read<SessionProvider>().connect(
          host,
          initialCommand:
              ContainerService.kubectlExecCommand(p.name, p.namespace, container),
        );
  }

  dynamic _hostForSelected() {
    final sessions = context.read<SessionProvider>().sessions;
    for (final s in sessions) {
      if (s.id == _sessionId) return s.host;
    }
    return sessions.isEmpty ? null : sessions.first.host;
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

- [ ] **Step 3: Verify it compiles**

Run: `cd app && flutter analyze lib/widgets/containers_screen.dart`
Expected: No errors. (If `AppColors.textTertiary` does not exist, open `app/lib/theme/app_theme.dart` and use the nearest existing muted-text color constant.)

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/containers_screen.dart
git commit -m "feat(containers): ContainersScreen UI"
```

---

## Task 6: Wire into the DevOps plugin hub

**Files:**
- Modify: `packages/yourssh_devops/lib/src/devops_plugin_config.dart`
- Modify: `packages/yourssh_devops/lib/src/screens/devops_hub_screen.dart`
- Modify: `app/lib/plugins/plugin_registry.dart`

- [ ] **Step 1: Add the config slot**

In `packages/yourssh_devops/lib/src/devops_plugin_config.dart`, add the field and constructor param:

```dart
  final Widget containersScreen;
```

```dart
    required this.containersScreen,
```

- [ ] **Step 2: Add the tool to the hub**

In `packages/yourssh_devops/lib/src/screens/devops_hub_screen.dart`:

Add `containers` to the enum:

```dart
enum _DevOpsTool { containers, networkTools, cloudflare, lanShare, mailCatcher, mcpServer, s3Browser }
```

Add to the `_buildContent()` switch:

```dart
        _DevOpsTool.containers  => widget.config.containersScreen,
```

Add a nav item in `_SubNav.build` (before Network Tools):

```dart
          _item(_DevOpsTool.containers, Icons.widgets_outlined, 'Containers'),
```

- [ ] **Step 3: Register the screen in the app**

In `app/lib/plugins/plugin_registry.dart`:

Add the import:

```dart
import '../widgets/containers_screen.dart';
```

Add to the `DevOpsPluginConfig(...)` constructor call:

```dart
      containersScreen: const ContainersScreen(),
```

- [ ] **Step 4: Verify analyze passes across the app**

Run: `cd app && flutter analyze`
Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add packages/yourssh_devops/lib/src/devops_plugin_config.dart packages/yourssh_devops/lib/src/screens/devops_hub_screen.dart app/lib/plugins/plugin_registry.dart
git commit -m "feat(containers): wire Containers screen into DevOps hub"
```

---

## Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole suite + analyzer**

Run: `cd app && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass (including the new `container_service_test.dart` and `ssh_session_initial_command_test.dart`).

- [ ] **Step 2: Manual smoke test**

Run: `cd app && flutter run -d macos`
- Open an SSH session to a host that has Docker. Go to DevOps → Containers.
- Verify the session dropdown shows the session, Docker list populates, and **Exec** opens a new tab that lands inside the container (`bash`/`sh` prompt).
- Switch to Kubernetes; verify pods list for `default` and the All-namespaces toggle. Exec into a pod (multi-container pod shows the picker).
- On a host without docker/kubectl, verify the install hint + Copy button appears.

- [ ] **Step 3: Update the changelog**

Per project convention (CLAUDE.md / memory), before a PR to master: move `[Unreleased]` → versioned section, add the feature line, refresh comparison links. Add under the appropriate version:

```
- Docker / Kubernetes container browser in DevOps: list `docker ps` containers
  and `kubectl get pods`, exec directly into them in a new terminal tab, with
  install hints when the runtime is missing.
```

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for Docker/Kubernetes exec"
```

---

## Self-Review Notes

- **Spec coverage:** Docker list (T1), K8s list (T2), runtime detect + install/permission hints (T3), new-tab exec via `initialCommand` (T4), screen with session dropdown / namespace / all-ns / Exec / multi-container picker / states (T5), DevOps-hub wiring (T6), verification + changelog (T7). All spec sections mapped.
- **Type consistency:** `ContainerEntry`, `PodEntry`, `RuntimeAvailability`, `RuntimeStatus` defined in T1, used unchanged in T2/T3/T5. `dockerExecCommand`/`kubectlExecCommand`/`installHint`/`permissionHint`/`classifyRuntime`/`parseDockerPs`/`parsePods`/`parseContainerNames` are all static on `ContainerService`; instance methods `listDockerContainers`/`listPods`/`podContainers`/`detectRuntimes` take `Host`. `connect(host, {initialCommand})` matches `SshSession(initialCommand:)` → `openShell` read.
- **Deferred (per spec):** logs/stop/restart, running install commands directly, sudo-docker toggle, auto-refresh.
```
