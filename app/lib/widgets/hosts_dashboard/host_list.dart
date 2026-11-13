part of 'hosts_dashboard.dart';

// ── Host List ─────────────────────────────────────────────

class _HostList extends StatelessWidget {
  final List<Host> hosts;
  final _SessionStats sessionStats;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Host)? onToggleSelect;
  const _HostList({
    required this.hosts,
    this.sessionStats = _SessionStats.empty,
    this.onEditHost,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final h in hosts)
          Padding(
            padding: const EdgeInsets.only(bottom: YsSpace.s2),
            child: _HostCard(
              key: ValueKey('host-card-${h.id}'),
              host: h,
              compact: true,
              onEditHost: onEditHost,
              selectionMode: selectionMode,
              selected: selectedIds.contains(h.id),
              onToggleSelect: () => onToggleSelect?.call(h),
              openSessions: sessionStats.open[h.id] ?? 0,
              live: sessionStats.live.contains(h.id),
              hasSshSession: sessionStats.ssh.contains(h.id),
            ),
          ),
      ],
    );
  }
}
