import 'dart:async';
import '../models/host.dart';
import '../models/network_stats.dart';
import 'ssh_service.dart';

class NetworkStatsService {
  Timer? _timer;
  NetworkStats? _previous;
  final void Function(NetworkStatsDelta delta) onUpdate;
  final Host host;
  final SshService sshService;

  NetworkStatsService({
    required this.host,
    required this.sshService,
    required this.onUpdate,
  });

  void start({Duration interval = const Duration(seconds: 2)}) {
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final result = await sshService.exec(host,
          'cat /proc/net/dev 2>/dev/null || netstat -ib 2>/dev/null',
          // periodic poll — auditing would flood the log
          auditSource: null);
      final output = result.stdout;
      if (output.isEmpty) return;
      final iface = detectPrimaryInterface(output);
      if (iface == null) return;
      final current = NetworkStats.fromProcNetDev(output, interface: iface);
      if (_previous != null) {
        onUpdate(current.delta(_previous!));
      }
      _previous = current;
    } catch (_) {
      // SSH exec may fail if session disconnects — silently ignore
    }
  }

  static String? detectPrimaryInterface(String procNetDevOutput) {
    for (final line in procNetDevOutput.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Inter') || trimmed.startsWith('face')) continue;
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) continue;
      final name = trimmed.substring(0, colonIdx).trim();
      if (name == 'lo') continue;
      return name;
    }
    return null;
  }
}
