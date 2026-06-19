import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import 'ssh_service.dart';

/// Lists Docker containers / Kubernetes pods on a remote host and detects
/// which container runtimes are available. Parsing is done by stateless
/// functions so it can be unit-tested without an SSH connection.
class ContainerService {
  final SshService ssh;
  ContainerService(this.ssh);

  // ── Docker ────────────────────────────────────────────
  static const _dockerFormat = '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}';

  Future<List<ContainerEntry>> listDockerContainers(Host host) async {
    final r = await ssh.exec(host, "docker ps -a --format '$_dockerFormat'", auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker ps failed' : r.stderr.trim());
    }
    return parseDockerPs(r.stdout);
  }

  // ── Docker logs + lifecycle ───────────────────────────

  /// Streams stdout+stderr of `docker logs -f <id>`.
  Stream<String> streamDockerLogs(Host host, String id, {int tail = 100}) =>
      ssh.execStream(host, 'docker logs -f --tail=$tail $id 2>&1',
          auditSource: 'devops');

  Future<void> stopContainer(Host host, String id) async {
    final r = await ssh.exec(host, 'docker stop ${_shq(id)}', auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker stop failed' : r.stderr.trim());
    }
  }

  Future<void> startContainer(Host host, String id) async {
    final r = await ssh.exec(host, 'docker start ${_shq(id)}', auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker start failed' : r.stderr.trim());
    }
  }

  Future<void> restartContainer(Host host, String id) async {
    final r = await ssh.exec(host, 'docker restart ${_shq(id)}', auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'docker restart failed' : r.stderr.trim());
    }
  }

  // ── Kubernetes ────────────────────────────────────────
  Future<List<PodEntry>> listPods(
    Host host, {
    String namespace = 'default',
    bool allNamespaces = false,
    String? context,
  }) async {
    final scope = allNamespaces ? '-A' : '-n $namespace';
    final ctxFlag = context != null ? ' --context=$context' : '';
    final r = await ssh.exec(host, 'kubectl get pods $scope$ctxFlag',
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(r.stderr.trim().isEmpty ? 'kubectl failed' : r.stderr.trim());
    }
    return parsePods(r.stdout, namespace: namespace, allNamespaces: allNamespaces);
  }

  Future<List<String>> podContainers(Host host, String pod, String namespace) async {
    final r = await ssh.exec(host,
        "kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[*].name}'",
        auditSource: 'devops');
    if (r.exitCode != 0) return const [];
    return parseContainerNames(r.stdout);
  }

  // ── Contexts ──────────────────────────────────────────

  Future<List<String>> listContexts(Host host) async {
    final r = await ssh.exec(host, 'kubectl config get-contexts -o name',
        auditSource: 'devops');
    if (r.exitCode != 0) return const [];
    return parseContextNames(r.stdout);
  }

  Future<String?> currentContext(Host host) async {
    final r = await ssh.exec(host, 'kubectl config current-context',
        auditSource: 'devops');
    if (r.exitCode != 0) return null;
    final name = r.stdout.trim();
    return name.isEmpty ? null : name;
  }

  static List<String> parseContextNames(String stdout) {
    return stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  // ── Log streaming ─────────────────────────────────────

  /// Streams stdout lines from `kubectl logs -f`.
  /// Cancel the subscription to stop the stream and close the SSH channel.
  Stream<String> streamLogs(
    Host host,
    String pod,
    String namespace,
    String? context, {
    String? container,
    int tail = 100,
  }) {
    final ctxFlag = context != null ? ' --context=$context' : '';
    final cFlag = container != null ? ' -c $container' : '';
    final cmd =
        'kubectl logs -f $pod -n $namespace --tail=$tail$ctxFlag$cFlag';
    return ssh.execStream(host, cmd, auditSource: 'devops');
  }

  // ── Port forwarding ───────────────────────────────────

  /// Starts `kubectl port-forward` on [host] and creates a local [ServerSocket]
  /// on [localPort] that tunnels connections to the pod via SSH.
  ///
  /// Throws [TimeoutException] if kubectl does not print "Forwarding from"
  /// within 10 seconds, or any [Exception] on kubectl error.
  Future<K8sForwardHandle> startPodPortForward(
    Host host,
    String pod,
    String namespace,
    String? context,
    int podPort,
    int localPort,
  ) async {
    final remotePfPort = 40000 + Random().nextInt(10000);
    final ctxFlag = context != null ? ' --context=$context' : '';
    final cmd = 'kubectl port-forward --address 0.0.0.0 pod/$pod '
        '$remotePfPort:$podPort -n $namespace$ctxFlag';

    final ready = Completer<void>();
    final lines = <String>[];
    final logStream = ssh.execStream(host, cmd, auditSource: 'devops');

    late StreamSubscription<String> kubectlSub;
    kubectlSub = logStream.listen(
      (line) {
        // Accumulate only until forwarding is confirmed. `lines` is read solely
        // for the early-exit error message in onDone, so appending after `ready`
        // completes would grow the buffer unbounded for the lifetime of the
        // forward (kubectl logs one line per proxied connection). Keep draining
        // the stream — just stop holding onto the lines.
        if (ready.isCompleted) return;
        lines.add(line);
        if (line.contains('Forwarding from')) ready.complete();
      },
      onError: (e) {
        if (!ready.isCompleted) ready.completeError(e);
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            Exception('kubectl exited: ${lines.join(' | ')}'),
          );
        }
      },
    );

    try {
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (e) {
      await kubectlSub.cancel();
      rethrow;
    }

    final client = await ssh.ensureClient(host);
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    final closers = <void Function()>[];

    final serverSub = server.listen((socket) async {
      try {
        final channel = await client.forwardLocal('localhost', remotePfPort);
        _pipeK8s(socket, channel, closers);
      } catch (_) {
        socket.destroy();
      }
    });

    return K8sForwardHandle(
      pod: pod,
      namespace: namespace,
      podPort: podPort,
      localPort: localPort,
      kubectlSub: kubectlSub,
      server: server,
      serverSub: serverSub,
      closers: closers,
    );
  }

  static void _pipeK8s(
      Socket local, SSHSocket remote, List<void Function()> closers) {
    var done = false;
    late final void Function() finish;
    finish = () {
      if (done) return;
      done = true;
      local.destroy();
      remote.destroy();
      closers.remove(finish);
    };
    closers.add(finish);
    unawaited(remote.stream
        .cast<List<int>>()
        .pipe(local)
        .catchError((_) {})
        .whenComplete(finish));
    unawaited(local
        .cast<List<int>>()
        .pipe(remote.sink)
        .catchError((_) {})
        .whenComplete(finish));
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

  // ── Runtime detection ─────────────────────────────────
  Future<RuntimeStatus> detectRuntimes(Host host) async {
    // The two runtimes are independent — probe them concurrently.
    final results = await Future.wait([
      _detectOne(host, 'docker', 'docker ps'),
      _detectOne(host, 'kubectl', 'kubectl version --client'),
    ]);
    return RuntimeStatus(docker: results[0], kubectl: results[1]);
  }

  Future<RuntimeAvailability> _detectOne(Host host, String cmd, String probe) async {
    final exists = await ssh.exec(host, 'command -v $cmd', auditSource: 'devops');
    if (exists.exitCode != 0) return RuntimeAvailability.notInstalled;
    final p = await ssh.exec(host, probe, auditSource: 'devops');
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

  // ── Shell quoting ─────────────────────────────────────
  /// POSIX single-quote-escapes [s] for safe shell interpolation.
  static String _shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

  // ── Exec command builders ─────────────────────────────
  static const _shFallback =
      "sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'";

  static String dockerExecCommand(String id) =>
      'docker exec -it $id $_shFallback';

  static String kubectlExecCommand(
      String pod, String namespace, String? container) {
    final containerFlag = container == null ? '' : '-c $container ';
    return 'kubectl exec -it $pod -n $namespace $containerFlag-- $_shFallback';
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
        : r'curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/';
  }

  static String permissionHint(String runtime) {
    if (runtime == 'docker') {
      return r'sudo usermod -aG docker $USER   # then log out and back in';
    }
    return 'Check your kubeconfig / RBAC permissions.';
  }

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
        final projectDir = firstFile.contains('/')
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
      if (projectDir.isEmpty) continue;
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
      final group = e.value;
      final first = group.first;
      final states = group.map((m) => (m['State'] as String? ?? '').trim()).toList();
      final String status;
      if (states.every((s) => s == 'running')) {
        status = 'running';
      } else if (states.any((s) => s == 'running')) {
        status = 'degraded';
      } else {
        status = states.first;
      }
      return ComposeService(
        name: e.key,
        status: status,
        image: (first['Image'] as String? ?? '').trim(),
        replicas: group.length,
      );
    }).toList();
  }

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
        host, "cd ${_shq(stack.projectDir)} && docker compose ps --format json 2>/dev/null",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose ps failed' : r.stderr.trim());
    }
    return parseComposePs(r.stdout);
  }

  Future<void> composeUp(Host host, ComposeStack stack) async {
    final r = await ssh.exec(
        host, "cd ${_shq(stack.projectDir)} && docker compose up -d",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose up failed' : r.stderr.trim());
    }
  }

  Future<void> composeDown(Host host, ComposeStack stack) async {
    final r = await ssh.exec(
        host, "cd ${_shq(stack.projectDir)} && docker compose down",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose down failed' : r.stderr.trim());
    }
  }

  Future<void> startComposeService(
      Host host, ComposeStack stack, String service) async {
    final r = await ssh.exec(
        host, "cd ${_shq(stack.projectDir)} && docker compose start ${_shq(service)}",
        auditSource: 'devops');
    if (r.exitCode != 0) {
      throw Exception(
          r.stderr.trim().isEmpty ? 'docker compose start failed' : r.stderr.trim());
    }
  }

  Future<void> stopComposeService(
      Host host, ComposeStack stack, String service) async {
    final r = await ssh.exec(
        host, "cd ${_shq(stack.projectDir)} && docker compose stop ${_shq(service)}",
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
          "cd ${_shq(stack.projectDir)} && docker compose logs -f --tail=$tail ${_shq(service)} 2>&1",
          auditSource: 'devops');

  /// Validates a Compose file at [path] by listing its services. Returns the
  /// service names; throws on a non-Compose / invalid file.
  Future<List<String>> validateComposeFile(Host host, String path) async {
    final r = await ssh.exec(host, 'docker compose -f ${_shq(path)} config --services 2>&1',
        auditSource: 'devops');
    if (r.exitCode != 0) {
      final detail = r.stdout.trim();
      throw Exception(detail.isEmpty ? 'Not a valid Compose file: $path' : 'Not a valid Compose file: $path — $detail');
    }
    return r.stdout.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }
}
