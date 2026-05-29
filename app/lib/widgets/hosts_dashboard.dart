import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import 'sftp_screen.dart';

class HostsDashboard extends StatefulWidget {
  final VoidCallback? onAddHost;
  final void Function(Host)? onEditHost;
  final VoidCallback? onOpenLocalTerminal;
  final void Function(String group)? onNewGroup;
  const HostsDashboard({super.key, this.onAddHost, this.onEditHost, this.onOpenLocalTerminal, this.onNewGroup});

  @override
  State<HostsDashboard> createState() => _HostsDashboardState();
}

class _HostsDashboardState extends State<HostsDashboard> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final hostProvider = context.watch<HostProvider>();
    final hosts = hostProvider.hosts;
    final filtered = _search.isEmpty
        ? hosts
        : hosts.where((h) =>
            h.label.toLowerCase().contains(_search.toLowerCase()) ||
            h.host.toLowerCase().contains(_search.toLowerCase()) ||
            h.username.toLowerCase().contains(_search.toLowerCase())).toList();

    final groups = <String, List<Host>>{};
    for (final h in hosts) {
      final g = h.group.isEmpty ? 'DEFAULT' : h.group.toUpperCase();
      (groups[g] ??= []).add(h);
    }

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _TopBar(
            search: _search,
            onSearch: (v) => setState(() => _search = v),
            totalHosts: hosts.length,
            filteredCount: filtered.length,
            onAddHost: widget.onAddHost,
            onLocalTerminal: widget.onOpenLocalTerminal,
            onNewGroup: widget.onNewGroup,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_search.isEmpty) ...[
                    _SectionHeader(title: 'Groups', count: '${groups.length} group${groups.length == 1 ? '' : 's'}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: groups.entries
                          .map((e) => _GroupCard(name: e.key, count: e.value.length))
                          .toList(),
                    ),
                    const SizedBox(height: 32),
                  ],

                  Row(
                    children: [
                      Expanded(child: _SectionHeader(title: 'Hosts', count: '${filtered.length} of ${hosts.length} hosts')),
                      if (filtered.isEmpty && _search.isNotEmpty)
                        Text('No results', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty && _search.isEmpty)
                    _EmptyState(onAdd: widget.onAddHost ?? () {})
                  else
                    _HostGrid(hosts: filtered, onEditHost: widget.onEditHost),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Top Bar ───────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearch;
  final int totalHosts;
  final int filteredCount;
  final VoidCallback? onAddHost;
  final VoidCallback? onLocalTerminal;
  final void Function(String group)? onNewGroup;

  const _TopBar({required this.search, required this.onSearch, required this.totalHosts, required this.filteredCount, this.onAddHost, this.onLocalTerminal, this.onNewGroup});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                onChanged: onSearch,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search hosts, IPs, or tags...',
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.search, color: AppColors.textTertiary, size: 16),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$filteredCount of $totalHosts hosts',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 16),
          _OutlinedBtn(
            icon: Icons.terminal,
            label: 'LOCAL TERMINAL',
            onTap: onLocalTerminal ?? () {},
          ),
          const SizedBox(width: 8),
          _OutlinedBtn(
            icon: Icons.add,
            label: 'NEW HOST',
            onTap: onAddHost ?? () {},
          ),
        ],
      ),
    );
  }
}

class _OutlinedBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OutlinedBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(count, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      ],
    );
  }
}

// ── Group Card ────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final String name;
  final int count;
  const _GroupCard({required this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.textTertiary.withValues(alpha: 0.3),
            child: Icon(Icons.folder_outlined, color: AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              Text('$count host${count == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Host Grid ─────────────────────────────────────────────

class _HostGrid extends StatelessWidget {
  final List<Host> hosts;
  final void Function(Host)? onEditHost;
  const _HostGrid({required this.hosts, this.onEditHost});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const minCardWidth = 280.0;
        const spacing = 12.0;
        final cols = (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 4);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: hosts
              .map((h) => SizedBox(
                    width: (constraints.maxWidth - spacing * (cols - 1)) / cols,
                    child: _HostCard(host: h, onEditHost: onEditHost),
                  ))
              .toList(),
        );
      },
    );
  }
}

// ── Host Card ─────────────────────────────────────────────

class _HostCard extends StatefulWidget {
  final Host host;
  final void Function(Host)? onEditHost;
  const _HostCard({required this.host, this.onEditHost});

  @override
  State<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<_HostCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.hostColor(widget.host.id);
    final sessionProvider = context.read<SessionProvider>();
    final hostProvider = context.read<HostProvider>();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onDoubleTap: () => sessionProvider.connect(widget.host),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hovered ? AppColors.border.withValues(alpha: 0.8) : AppColors.border),
          ),
          child: Row(
            children: [
              // Host icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dns, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),

              // Host info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Status dot
                        Container(
                          width: 6, height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: AppColors.red, // offline by default
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.host.label,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.host.username}@${widget.host.host}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Action buttons (show on hover)
              if (_hovered) ...[
                _iconBtn(Icons.folder_outlined, 'SFTP', onTap: () => _openSftp(context)),
                const SizedBox(width: 2),
                _iconBtn(Icons.more_horiz, 'More', onTapDown: (d) => _showMenu(context, hostProvider, sessionProvider, d.globalPosition)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, {VoidCallback? onTap, void Function(TapDownDetails)? onTapDown}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        onTapDown: onTapDown,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 14, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, HostProvider hostProvider, SessionProvider sessionProvider, Offset tapPosition) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromRect(
        tapPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        _menuItem('terminal', Icons.terminal, 'Connect', () => sessionProvider.connect(widget.host)),
        _menuItem('sftp', Icons.folder_outlined, 'SFTP', () => _openSftp(context)),
        _menuItem('edit', Icons.edit_outlined, 'Edit', () => widget.onEditHost?.call(widget.host)),
        const PopupMenuDivider(),
        _menuItem('duplicate', Icons.copy_outlined, 'Duplicate', () => _duplicate(context, hostProvider)),
        _menuItem('copy_url', Icons.link_outlined, 'Copy SSH URL', () => _copySshUrl(context)),
        _menuItem('move_group', Icons.drive_file_move_outlined, 'Move to Group', () => _moveToGroup(context, hostProvider)),
        _menuItem('export', Icons.upload_outlined, 'Export', () => _export(context)),
        const PopupMenuDivider(),
        _menuItem('delete', Icons.delete_outlined, 'Delete', () => hostProvider.deleteHost(widget.host.id), color: AppColors.red),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, VoidCallback action, {Color? color}) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      onTap: action,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color ?? AppColors.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }

  void _copySshUrl(BuildContext context) {
    final url = 'ssh://${widget.host.username}@${widget.host.host}:${widget.host.port}';
    Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('SSH URL copied'), duration: Duration(seconds: 2)),
    );
  }

  void _duplicate(BuildContext context, HostProvider hostProvider) {}
  void _moveToGroup(BuildContext context, HostProvider hostProvider) {}
  void _export(BuildContext context) {}

  void _openSftp(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(40),
        child: SizedBox(
          width: 800,
          height: 600,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SftpScreen(host: widget.host),
          ),
        ),
      ),
    );
  }

}

// ── Empty State ───────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 52, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No hosts yet', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Add your first SSH host to get started', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                child: const Text('+ New Host', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
