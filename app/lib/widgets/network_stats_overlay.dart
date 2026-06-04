import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_stats.dart';
import '../models/ssh_session.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/network_stats_service.dart';
import '../services/ssh_service.dart';

class NetworkStatsOverlay extends StatefulWidget {
  const NetworkStatsOverlay({super.key});

  @override
  State<NetworkStatsOverlay> createState() => _NetworkStatsOverlayState();
}

class _NetworkStatsOverlayState extends State<NetworkStatsOverlay> {
  NetworkStatsService? _service;
  NetworkStatsDelta? _delta;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resetService();
  }

  void _resetService() {
    _service?.stop();
    // Stats are for the focused session — hide on local tabs rather than
    // falling back to another host's numbers.
    final active = context.read<SessionProvider>().activeSession;
    final session = active is SshSession ? active : null;
    if (session == null) return;
    _service = NetworkStatsService(
      host: session.host,
      sshService: context.read<SshService>(),
      onUpdate: (delta) => setState(() => _delta = delta),
    );
    _service!.start();
  }

  @override
  void dispose() {
    _service?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.networkStatsEnabled || _delta == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_downward, size: 12, color: Color(0xFF22C55E)),
          const SizedBox(width: 2),
          Text(
            NetworkStats.formatBytes(_delta!.rxBytesPerSec),
            style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_upward, size: 12, color: Color(0xFF60A5FA)),
          const SizedBox(width: 2),
          Text(
            NetworkStats.formatBytes(_delta!.txBytesPerSec),
            style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
