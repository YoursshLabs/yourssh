import 'dart:async';
import '../models/firewall_status.dart';
import '../models/host.dart';
import 'ssh_service.dart';

class FirewallStatusService {
  Timer? _timer;
  final Host host;
  final SshService sshService;
  final void Function(FirewallStatus) onUpdate;

  FirewallStatusService({
    required this.host,
    required this.sshService,
    required this.onUpdate,
  });

  void start({Duration interval = const Duration(seconds: 30)}) {
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
      onUpdate(FirewallStatus.fromShellOutput(result.stdout));
    } catch (_) {}
  }
}

const _kCommand =
    'ufw status numbered 2>/dev/null || '
    'iptables-save 2>/dev/null || '
    'nft list ruleset 2>/dev/null || '
    'echo __NO_FIREWALL__';
