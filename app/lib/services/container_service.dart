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
