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
