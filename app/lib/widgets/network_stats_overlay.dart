import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_stats.dart';
import '../models/ssh_session.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/network_stats_service.dart';
import '../services/ssh_service.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class NetworkStatsOverlay extends StatefulWidget {
  const NetworkStatsOverlay({super.key});

  @override
  State<NetworkStatsOverlay> createState() => _NetworkStatsOverlayState();
}

class _NetworkStatsOverlayState extends State<NetworkStatsOverlay> {
  NetworkStatsService? _service;
  NetworkStatsDelta? _delta;
  String? _watchedSessionId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // watch (not read): tab switches must re-evaluate which session the
    // stats belong to — with a plain read this never re-ran and the overlay
    // kept polling (and rendering) the previous host on local tabs.
    final active = context.watch<SessionProvider>().activeSession;
    final session = active is SshSession ? active : null;
    if (session?.id == _watchedSessionId) return;
    _watchedSessionId = session?.id;
    _resetService(session);
  }

  void _resetService(SshSession? session) {
    _service?.stop();
    _service = null;
    // Stats are for the focused session — hide on local tabs (and drop the
    // previous host's numbers) rather than rendering them as if live here.
    _delta = null;
    if (session == null) return;
    _service = NetworkStatsService(
      host: session.host,
      sshService: context.read<SshService>(),
      onUpdate: (delta) => setState(() => _delta = delta),
    );
    _service!.start();
  }

  @visibleForTesting
  void debugSetDelta(NetworkStatsDelta delta) {
    setState(() => _delta = delta);
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

    const mono = TextStyle(
      fontSize: 11,
      fontFamily: kYsMonoFontFamily,
      fontFamilyFallback: kYsMonoFontFallback,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s2, vertical: YsSpace.s1 - 1),
      decoration: BoxDecoration(
        color: YsColors.card.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(YsRadius.control),
        border: Border.all(color: YsColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FLucideIcons.arrowDown,
              size: 12, color: YsColors.accentText),
          const SizedBox(width: 2),
          Text(
            NetworkStats.formatBytes(_delta!.rxBytesPerSec),
            style: mono.copyWith(color: YsColors.accentText),
          ),
          const SizedBox(width: YsSpace.s2),
          const Icon(FLucideIcons.arrowUp, size: 12, color: YsColors.foreground),
          const SizedBox(width: 2),
          Text(
            NetworkStats.formatBytes(_delta!.txBytesPerSec),
            style: mono.copyWith(color: YsColors.foreground),
          ),
        ],
      ),
    );
  }
}
