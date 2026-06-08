import 'dart:async';
import '../models/host.dart';
import '../models/system_snapshot.dart';
import 'ssh_service.dart';

class SystemStatsService {
  Timer? _timer;
  final Host host;
  final SshService sshService;
  final void Function(SystemSnapshot) onUpdate;

  SystemStatsService({
    required this.host,
    required this.sshService,
    required this.onUpdate,
  });

  void start({Duration interval = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fires one poll cycle immediately. Exposed for tests.
  Future<void> poll() async {
    try {
      final result = await sshService.exec(host, _kCommand, auditSource: null);
      if (result.stdout.isEmpty) return;
      onUpdate(SystemSnapshot.fromShellOutput(result.stdout));
    } catch (_) {}
  }
}

// Raw string concatenation — compiled to a single constant.
// The shell reads /proc/stat twice 200ms apart to compute CPU delta in one exec.
const _kCommand =
    r'c1=$(grep -m1 "^cpu " /proc/stat 2>/dev/null); sleep 0.2; '
    r'c2=$(grep -m1 "^cpu " /proc/stat 2>/dev/null); '
    r'printf "__CPU1__\n%s\n__CPU2__\n%s\n" "$c1" "$c2"; '
    r'printf "__MEM__\n"; cat /proc/meminfo 2>/dev/null; '
    r'printf "__DISK__\n"; df -k 2>/dev/null; '
    r'printf "__UPTIME__\n"; cat /proc/uptime 2>/dev/null; '
    r'printf "__PORTS__\n"; ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null';
