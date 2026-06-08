import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/firewall_status.dart';
import '../models/host.dart';
import '../models/system_snapshot.dart';
import '../providers/session_provider.dart';
import '../services/firewall_status_service.dart';
import '../services/ssh_service.dart';
import '../services/system_stats_service.dart';
import '../theme/app_theme.dart';

class ServerMonitorSheet extends StatefulWidget {
  final Host host;
  // Bypasses the SessionProvider check in tests — null means use the real check.
  @visibleForTesting
  final bool? testIsConnected;

  const ServerMonitorSheet({super.key, required this.host, this.testIsConnected});

  static void show(BuildContext context, Host host) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServerMonitorSheet(host: host),
    );
  }

  @override
  State<ServerMonitorSheet> createState() => ServerMonitorSheetState();
}

// Public so widget tests can cast via tester.state<ServerMonitorSheetState>().
class ServerMonitorSheetState extends State<ServerMonitorSheet> {
  SystemStatsService? _statsService;
  FirewallStatusService? _firewallService;
  SystemSnapshot? _snapshot;
  FirewallStatus? _firewall;
  String? _statsError;
  String? _firewallError;
  bool _started = false;

  @visibleForTesting
  void debugSetSnapshot(SystemSnapshot s) => setState(() => _snapshot = s);

  @visibleForTesting
  void debugSetFirewall(FirewallStatus f) => setState(() => _firewall = f);

  bool _isConnected(BuildContext context) =>
      widget.testIsConnected ??
      context
          .read<SessionProvider>()
          .sshSessions
          .any((s) => s.host.id == widget.host.id);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!_isConnected(context)) return;
    final ssh = context.read<SshService>();
    _statsService = SystemStatsService(
      host: widget.host,
      sshService: ssh,
      onUpdate: (s) {
        if (mounted) setState(() { _snapshot = s; _statsError = null; });
      },
      onError: (e) {
        if (mounted) setState(() => _statsError = e.toString());
      },
    );
    _firewallService = FirewallStatusService(
      host: widget.host,
      sshService: ssh,
      onUpdate: (f) {
        if (mounted) setState(() { _firewall = f; _firewallError = null; });
      },
      onError: (e) {
        if (mounted) setState(() => _firewallError = e.toString());
      },
    );
    _statsService!.start();
    _firewallService!.start();
    // Deliver first reading immediately rather than waiting for the first tick.
    _statsService!.poll();
    _firewallService!.poll();
  }

  @override
  void dispose() {
    _statsService?.stop();
    _firewallService?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _isConnected(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: Column(children: [
          _handle(),
          _header(),
          Expanded(
            child: isConnected ? _body(ctrl) : _notConnected(),
          ),
        ]),
      ),
    );
  }

  Widget _handle() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3A),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Text(
            widget.host.label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_snapshot != null)
            Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Live',
                style: TextStyle(color: AppColors.accent, fontSize: 11),
              ),
            ]),
        ]),
      );

  Widget _notConnected() => const Center(
        child: Text(
          'No active session — open a terminal first',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );

  Widget _body(ScrollController ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _sectionTitle('SYSTEM'),
          if (_statsError != null && _snapshot == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Failed to load stats: $_statsError',
                style: TextStyle(color: Colors.red.shade300, fontSize: 12),
              ),
            )
          else if (_snapshot == null)
            const Center(child: CircularProgressIndicator())
          else
            _systemSection(_snapshot!),
          const SizedBox(height: 16),
          _sectionTitle('PORTS'),
          if (_statsError != null && _snapshot == null)
            const SizedBox.shrink()
          else if (_snapshot == null)
            const Center(child: CircularProgressIndicator())
          else
            _portsSection(_snapshot!.ports),
          const SizedBox(height: 16),
          _sectionTitle('FIREWALL'),
          if (_firewallError != null && _firewall == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Failed to load firewall: $_firewallError',
                style: TextStyle(color: Colors.red.shade300, fontSize: 12),
              ),
            )
          else if (_firewall == null)
            const Center(child: CircularProgressIndicator())
          else
            _firewallSection(_firewall!),
        ],
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _systemSection(SystemSnapshot s) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statRow('Uptime', SystemSnapshot.formatUptime(s.uptime)),
          const SizedBox(height: 6),
          _barRow(
            'CPU',
            s.cpuPercent / 100,
            '${s.cpuPercent.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 6),
          _barRow(
            'Memory',
            s.totalMemBytes == 0 ? 0 : s.usedMemBytes / s.totalMemBytes,
            '${SystemSnapshot.formatBytes(s.usedMemBytes)} / '
                '${SystemSnapshot.formatBytes(s.totalMemBytes)}',
          ),
          ...s.disks.map((d) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _barRow(
                  d.mountPoint,
                  d.usedPercent,
                  '${(d.usedPercent * 100).toStringAsFixed(0)}% of '
                      '${SystemSnapshot.formatBytes(d.totalKb * 1024)}',
                ),
              )),
        ],
      );

  Widget _statRow(String label, String value) => Row(children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
      ]);

  Widget _barRow(String label, double fraction, String right) => Row(children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFF2A2A2A),
              color: fraction > 0.85 ? AppColors.red : AppColors.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          right,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ]);

  Widget _portsSection(List<PortEntry> ports) {
    if (ports.isEmpty) {
      return const Text(
        'No listening ports detected',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return Column(
      children: ports
          .map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      p.protocol,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      ':${p.localPort}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      p.process ?? '—',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ))
          .toList(),
    );
  }

  Widget _firewallSection(FirewallStatus fw) {
    if (fw.type == FirewallType.none) {
      return const Text(
        'No firewall detected',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _chip(fw.type.name, AppColors.accent),
          const SizedBox(width: 6),
          _chip(
            fw.enabled ? 'active' : 'inactive',
            fw.enabled ? AppColors.accent : AppColors.red,
          ),
          if (fw.defaultInboundPolicy != null) ...[
            const SizedBox(width: 8),
            Text(
              'default inbound: ${fw.defaultInboundPolicy}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ]),
        if (fw.rules.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...fw.rules.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  r.description,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )),
        ],
      ],
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      );
}
