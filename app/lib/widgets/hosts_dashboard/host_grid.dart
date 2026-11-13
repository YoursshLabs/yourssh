part of 'hosts_dashboard.dart';

// ── Host Grid ─────────────────────────────────────────────

class _HostGrid extends StatelessWidget {
  final List<Host> hosts;
  final _SessionStats sessionStats;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Host)? onToggleSelect;
  const _HostGrid({
    required this.hosts,
    this.sessionStats = _SessionStats.empty,
    this.onEditHost,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const minCardWidth = 280.0;
        const spacing = YsSpace.s3;
        final cols = (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 4);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: hosts
              .map((h) => SizedBox(
                    width: (constraints.maxWidth - spacing * (cols - 1)) / cols,
                    child: _HostCard(
                      key: ValueKey('host-card-${h.id}'),
                      host: h,
                      onEditHost: onEditHost,
                      selectionMode: selectionMode,
                      selected: selectedIds.contains(h.id),
                      onToggleSelect: () => onToggleSelect?.call(h),
                      openSessions: sessionStats.open[h.id] ?? 0,
                      live: sessionStats.live.contains(h.id),
                      hasSshSession: sessionStats.ssh.contains(h.id),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}
