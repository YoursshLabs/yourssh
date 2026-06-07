import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/rdp_session.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import '../util/bulk_connect.dart';
import '../util/host_query.dart';
import '../util/host_sort.dart';
import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/os_detection.dart';
import '../services/ssh_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'rdp_badge.dart';
import 'bulk/bulk_action_bar.dart';
import 'bulk/bulk_push_dialog.dart';
import 'bulk/bulk_run_dialog.dart';
import 'sftp_screen.dart';

class HostsDashboard extends StatefulWidget {
  final VoidCallback? onAddHost;
  final void Function(Host)? onEditHost;
  final VoidCallback? onOpenLocalTerminal;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  const HostsDashboard({super.key, this.onAddHost, this.onEditHost, this.onOpenLocalTerminal, this.onNewGroup, this.onImport});

  @override
  State<HostsDashboard> createState() => _HostsDashboardState();
}

class _HostsDashboardState extends State<HostsDashboard> {
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  bool _selectionMode = false;
  final Set<String> _selectedHostIds = {};

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onSelectionKey);
    _searchController.dispose();
    super.dispose();
  }

  void _enterSelectionMode() {
    if (_selectionMode) return;
    HardwareKeyboard.instance.addHandler(_onSelectionKey);
    setState(() => _selectionMode = true);
  }

  void _exitSelectionMode() {
    HardwareKeyboard.instance.removeHandler(_onSelectionKey);
    setState(() {
      _selectionMode = false;
      _selectedHostIds.clear();
    });
  }

  bool _onSelectionKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _exitSelectionMode();
      return true;
    }
    return false;
  }

  void _toggleSelected(Host host) {
    setState(() {
      if (!_selectedHostIds.remove(host.id)) _selectedHostIds.add(host.id);
    });
  }

  List<Host> _selectedHosts() => context
      .read<HostProvider>()
      .allHosts
      .where((h) => _selectedHostIds.contains(h.id))
      .toList();

  void _selectAllFiltered() {
    final hosts = context.read<HostProvider>().allHosts;
    final query = HostQuery.parse(_search);
    final filtered = query.isEmpty ? hosts : hosts.where(query.matches);
    setState(() => _selectedHostIds.addAll(filtered.map((h) => h.id)));
  }

  Future<void> _connectAll() async {
    final sessionProvider = context.read<SessionProvider>();
    final live = {
      for (final s in sessionProvider.sshSessions)
        if (s.status == SessionStatus.connecting ||
            s.status == SessionStatus.connected)
          s.host.id,
      // RDP tabs count as live too — without this an already-open RDP host
      // gets a duplicate tab on every CONNECT ALL.
      for (final s in sessionProvider.sessions.whereType<RdpSession>())
        if (s.status == RdpSessionStatus.connecting ||
            s.status == RdpSessionStatus.connected)
          s.host.id,
    };
    final plan =
        planConnectAll(selected: _selectedHosts(), liveHostIds: live);
    if (plan.toConnect.length > 5) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Open ${plan.toConnect.length} tabs?',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 15)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open all',
                    style: TextStyle(color: AppColors.accent))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    for (final h in plan.toConnect) {
      unawaited(sessionProvider.connectAny(h));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(plan.skipped > 0
          ? 'Opened ${plan.toConnect.length} tabs · ${plan.skipped} already connected'
          : 'Opened ${plan.toConnect.length} tabs'),
    ));
    _exitSelectionMode();
  }

  /// Bulk run/push are SSH operations — RDP hosts can never accept them and
  /// would only pollute the results with guaranteed failures.
  List<Host> _selectedSshHosts(String action) {
    final hosts = _selectedHosts();
    final ssh = hosts.where((h) => h.protocol == HostProtocol.ssh).toList();
    final skipped = hosts.length - ssh.length;
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$skipped RDP host(s) skipped — $action is SSH-only'),
      ));
    }
    return ssh;
  }

  void _openBulkRun() {
    final hosts = _selectedSshHosts('Run command');
    if (hosts.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkRunDialog(hosts: hosts),
    );
  }

  void _openBulkPush() {
    final hosts = _selectedSshHosts('Push files');
    if (hosts.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkPushDialog(hosts: hosts),
    );
  }

  void _toggleFacet(String facet) {
    final next = HostQuery.toggleToken(_search, facet);
    setState(() => _search = next);
    _searchController.text = next;
    _searchController.selection =
        TextSelection.collapsed(offset: next.length);
  }

  @override
  Widget build(BuildContext context) {
    final hostProvider = context.watch<HostProvider>();
    final hosts = hostProvider.allHosts;
    _selectedHostIds.removeWhere((id) => !hosts.any((h) => h.id == id));
    final query = HostQuery.parse(_search);
    final filtered =
        query.isEmpty ? hosts : hosts.where(query.matches).toList();
    final settings = context.watch<SettingsProvider>();
    final sortMode = HostSortMode.fromKey(settings.dashboardSort);
    final sorted = sortHosts(filtered, sortMode);
    final listView = settings.dashboardViewMode == 'list';
    final facets = HostQuery.availableFacets(hosts);

    final pinnedGroupsUpper =
        hostProvider.pinnedGroups.map((g) => g.toUpperCase()).toSet();
    final groups = <String, List<Host>>{};
    // Pinned groups appear first (may be empty)
    for (final g in pinnedGroupsUpper) {
      groups[g] = [];
    }
    // Fill with hosts (may add new groups not in pinnedGroups)
    for (final h in hosts) {
      final g = h.group.isEmpty ? 'DEFAULT' : h.group.toUpperCase();
      (groups[g] ??= []).add(h);
    }

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _selectionMode
              ? BulkActionBar(
                  selectedCount: _selectedHostIds.length,
                  onSelectAll: _selectAllFiltered,
                  onClear: () => setState(_selectedHostIds.clear),
                  onConnectAll: _connectAll,
                  onRunCommand: _openBulkRun,
                  onPushFiles: _openBulkPush,
                  onDone: _exitSelectionMode,
                )
              : _TopBar(
                  controller: _searchController,
                  onSearch: (v) => setState(() => _search = v),
                  totalHosts: hosts.length,
                  filteredCount: filtered.length,
                  onAddHost: widget.onAddHost,
                  onLocalTerminal: widget.onOpenLocalTerminal,
                  onNewGroup: widget.onNewGroup,
                  onImport: widget.onImport,
                  onSelect: _enterSelectionMode,
                  sortMode: sortMode,
                  onSortChanged: (m) =>
                      context.read<SettingsProvider>().save(dashboardSort: m.key),
                  viewMode: settings.dashboardViewMode,
                  onViewChanged: (v) => context
                      .read<SettingsProvider>()
                      .save(dashboardViewMode: v),
                ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (facets.isNotEmpty) ...[
                    _FacetChipBar(
                      facets: facets,
                      query: _search,
                      onToggle: _toggleFacet,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_search.isEmpty) ...[
                    _SectionHeader(title: 'Groups', count: '${groups.length} group${groups.length == 1 ? '' : 's'}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: groups.entries
                          .map((e) {
                            final isPinned = pinnedGroupsUpper.contains(e.key);
                            return _GroupCard(
                              name: e.key,
                              count: e.value.length,
                              onDelete: (isPinned && e.value.isEmpty)
                                  ? () => context.read<HostProvider>().removeGroup(e.key)
                                  : null,
                            );
                          })
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
                  else if (listView)
                    _HostList(
                      hosts: sorted,
                      onEditHost: widget.onEditHost,
                      selectionMode: _selectionMode,
                      selectedIds: _selectedHostIds,
                      onToggleSelect: _toggleSelected,
                    )
                  else
                    _HostGrid(
                      hosts: sorted,
                      onEditHost: widget.onEditHost,
                      selectionMode: _selectionMode,
                      selectedIds: _selectedHostIds,
                      onToggleSelect: _toggleSelected,
                    ),
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
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final int totalHosts;
  final int filteredCount;
  final VoidCallback? onAddHost;
  final VoidCallback? onLocalTerminal;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  final VoidCallback? onSelect;
  final HostSortMode sortMode;
  final ValueChanged<HostSortMode> onSortChanged;
  final String viewMode;
  final ValueChanged<String> onViewChanged;

  const _TopBar({
    required this.controller,
    required this.onSearch,
    required this.totalHosts,
    required this.filteredCount,
    this.onAddHost,
    this.onLocalTerminal,
    this.onNewGroup,
    this.onImport,
    this.onSelect,
    required this.sortMode,
    required this.onSortChanged,
    required this.viewMode,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(builder: (context, constraints) {
        // The action cluster keeps its natural width and the search field
        // absorbs the rest; once the window narrows past a minimum search
        // width (e.g. host panel open) the cluster scrolls instead of
        // overflowing — same pattern as BulkActionBar.
        const minSearchWidth = 180.0;
        final clusterMax =
            (constraints.maxWidth - minSearchWidth - 12).clamp(0.0, double.infinity);
        return Row(
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
                  controller: controller,
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
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: clusterMax),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$filteredCount of $totalHosts hosts',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(width: 16),
                    _SortBtn(mode: sortMode, onChanged: onSortChanged),
                    const SizedBox(width: 8),
                    _ViewToggle(viewMode: viewMode, onChanged: onViewChanged),
                    const SizedBox(width: 8),
                    _OutlinedBtn(
                      icon: Icons.check_box_outlined,
                      label: 'SELECT',
                      onTap: onSelect ?? () {},
                    ),
                    const SizedBox(width: 8),
                    _OutlinedBtn(
                      icon: Icons.terminal,
                      label: 'LOCAL TERMINAL',
                      onTap: onLocalTerminal ?? () {},
                    ),
                    const SizedBox(width: 8),
                    _SplitNewBtn(
                      onNewHost: onAddHost ?? () {},
                      onNewGroup: onNewGroup,
                      onImport: onImport,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
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

/// Dropdown button showing the current sort mode; opens a menu with all
/// HostSortMode values.
class _SortBtn extends StatelessWidget {
  final HostSortMode mode;
  final ValueChanged<HostSortMode> onChanged;
  const _SortBtn({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => _openMenu(context, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(mode.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.3)),
            const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<HostSortMode>(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final m in HostSortMode.values)
          PopupMenuItem<HostSortMode>(
            value: m,
            height: 36,
            child: Row(
              children: [
                Icon(Icons.check,
                    size: 14,
                    color: m == mode ? AppColors.accent : Colors.transparent),
                const SizedBox(width: 8),
                Text(m.label,
                    style: TextStyle(
                        color: m == mode ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 13)),
              ],
            ),
          ),
      ],
    );
    if (selected != null) onChanged(selected);
  }
}

/// Segmented grid/list switch for the hosts dashboard.
class _ViewToggle extends StatelessWidget {
  final String viewMode; // 'grid' | 'list'
  final ValueChanged<String> onChanged;
  const _ViewToggle({required this.viewMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment(Icons.grid_view, 'Grid view', 'grid'),
            Container(width: 1, height: 27, color: AppColors.border),
            _segment(Icons.view_list, 'List view', 'list'),
          ],
        ),
      ),
    );
  }

  Widget _segment(IconData icon, String tooltip, String mode) {
    final active = viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onChanged(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          color: active ? AppColors.card : Colors.transparent,
          child: Icon(icon, size: 13, color: active ? AppColors.textPrimary : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _SplitNewBtn extends StatefulWidget {
  final VoidCallback onNewHost;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  const _SplitNewBtn({
    required this.onNewHost,
    this.onNewGroup,
    this.onImport,
  });

  @override
  State<_SplitNewBtn> createState() => _SplitNewBtnState();
}

class _SplitNewBtnState extends State<_SplitNewBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _hovered ? AppColors.textSecondary : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: widget.onNewHost,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    const Text('NEW HOST',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 20, color: AppColors.border),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'group') widget.onNewGroup?.call();
                if (v == 'import') widget.onImport?.call();
              },
              color: AppColors.card,
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Icon(Icons.keyboard_arrow_down,
                    size: 14, color: AppColors.textSecondary),
              ),
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'group',
                  height: 36,
                  child: Row(
                    children: const [
                      Icon(Icons.create_new_folder_outlined,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 10),
                      Text('New Group',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'import',
                  height: 36,
                  child: Row(
                    children: const [
                      Icon(Icons.upload_file_outlined,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 10),
                      Text('Import',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
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

class _GroupCard extends StatefulWidget {
  final String name;
  final int count;
  final VoidCallback? onDelete;
  const _GroupCard({required this.name, required this.count, this.onDelete});

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text('${widget.count} host${widget.count == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (_hovered && widget.onDelete != null)
              GestureDetector(
                onTapDown: (d) => _showMenu(context, d.globalPosition),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.more_horiz,
                      size: 14, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          onTap: widget.onDelete,
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 14, color: AppColors.red),
              SizedBox(width: 10),
              Text('Delete group',
                  style: TextStyle(color: AppColors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Host Grid ─────────────────────────────────────────────

class _HostGrid extends StatelessWidget {
  final List<Host> hosts;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Host)? onToggleSelect;
  const _HostGrid({
    required this.hosts,
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
        const spacing = 12.0;
        final cols = (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 4);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: hosts
              .map((h) => SizedBox(
                    width: (constraints.maxWidth - spacing * (cols - 1)) / cols,
                    child: _HostCard(
                      host: h,
                      onEditHost: onEditHost,
                      selectionMode: selectionMode,
                      selected: selectedIds.contains(h.id),
                      onToggleSelect: () => onToggleSelect?.call(h),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

// ── Host List ─────────────────────────────────────────────

class _HostList extends StatelessWidget {
  final List<Host> hosts;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Host)? onToggleSelect;
  const _HostList({
    required this.hosts,
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
            padding: const EdgeInsets.only(bottom: 12),
            child: _HostCard(
              host: h,
              compact: true,
              onEditHost: onEditHost,
              selectionMode: selectionMode,
              selected: selectedIds.contains(h.id),
              onToggleSelect: () => onToggleSelect?.call(h),
            ),
          ),
      ],
    );
  }
}

// ── Host Card ─────────────────────────────────────────────

class _HostCard extends StatefulWidget {
  final Host host;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  /// false → grid card; true → single-line list row.
  final bool compact;
  const _HostCard({
    required this.host,
    this.onEditHost,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.compact = false,
  });

  @override
  State<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<_HostCard> {
  bool _hovered = false;
  bool _testing = false;
  ({bool success, int latencyMs, String? error})? _testResult;
  Timer? _resultTimer;

  @override
  void dispose() {
    _resultTimer?.cancel();
    super.dispose();
  }

  Widget _osIcon(Host host, {double pad = 8, double svg = 20, double fallback = 18}) {
    final asset = osIconAsset(host.detectedOs);
    if (asset != null) {
      return Padding(
        padding: EdgeInsets.all(pad),
        child: SvgPicture.asset(
          asset,
          width: svg,
          height: svg,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return Icon(Icons.dns, color: Colors.white, size: fallback);
  }

  Future<void> _test() async {
    if (_testing) return;
    _resultTimer?.cancel();
    setState(() { _testing = true; _testResult = null; });

    final sshService = context.read<SshService>();
    final storage = context.read<StorageService>();
    final keyProvider = context.read<KeyProvider>();
    final keys = keyProvider.keys;
    // Read all providers before the first await (no BuildContext across gaps).
    final hostsById = {
      for (final h in context.read<HostProvider>().allHosts) h.id: h
    };

    final password = widget.host.authType == AuthType.password
        ? await storage.loadPassword(widget.host.id)
        : null;

    SshKeyEntry? keyEntry;
    if (widget.host.authType == AuthType.privateKey && widget.host.keyId != null) {
      keyEntry = keys.where((k) => k.id == widget.host.keyId).firstOrNull;
    }

    // Test through the bastion chain, not a misleading direct dial.
    List<JumpHop> jumpChain;
    try {
      jumpChain = SshService.resolveJumpChain(
        widget.host,
        jumpLookup: (id) => hostsById[id],
        keyLookup: (id) => keyProvider.findById(id),
      );
    } on JumpChainException catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = (success: false, latencyMs: 0, error: e.message);
        });
      }
      return;
    }

    final result = await sshService.testConnection(
      widget.host,
      password: password,
      keyEntry: keyEntry,
      jumpChain: jumpChain,
    );

    if (!mounted) return;
    setState(() { _testing = false; _testResult = result; });
    _resultTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _testResult = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.hostColor(widget.host.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.selectionMode ? widget.onToggleSelect : null,
        onDoubleTap: widget.selectionMode
            ? null
            : () => context.read<SessionProvider>().connectAny(widget.host),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 14, vertical: widget.compact ? 8 : 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.selected ? AppColors.accent : _hovered ? AppColors.border.withValues(alpha: 0.8) : AppColors.border),
          ),
          child: widget.compact ? _compactRow(context, color) : _cardRow(context, color),
        ),
      ),
    );
  }

  Widget _selectionCheckbox() => SizedBox(
        width: 18,
        height: 18,
        child: Checkbox(
          value: widget.selected,
          onChanged: (_) => widget.onToggleSelect?.call(),
          activeColor: AppColors.accent,
          side: const BorderSide(color: AppColors.border),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  /// Hover actions / spinner / test result — shared by both layouts.
  /// [maxResultWidth] bounds the error text so a long message can't
  /// overflow the single-line list row.
  List<Widget> _trailing(BuildContext context, {double? maxResultWidth}) {
    Widget resultText = Text(
      _testResult == null
          ? ''
          : _testResult!.success
              ? '${_testResult!.latencyMs}ms'
              : (_testResult!.error ?? 'Failed'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: (_testResult?.success ?? false) ? AppColors.accent : AppColors.red,
        fontSize: 11,
      ),
    );
    if (maxResultWidth != null) {
      resultText = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxResultWidth),
        child: resultText,
      );
    }
    final isSsh = widget.host.protocol == HostProtocol.ssh;
    return [
      if (!widget.selectionMode && _hovered && !_testing && _testResult == null) ...[
        // Test/SFTP drive an SSH handshake — meaningless against an RDP port.
        if (isSsh) ...[
          _iconBtn(Icons.network_check, 'Test Connection', onTap: _test),
          const SizedBox(width: 2),
          _iconBtn(Icons.folder_outlined, 'SFTP', onTap: () => _openSftp(context)),
          const SizedBox(width: 2),
        ],
        _iconBtn(Icons.more_horiz, 'More', onTapDown: (d) => _showMenu(context, d.globalPosition)),
      ],
      if (_testing)
        const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary),
        ),
      if (_testResult != null) ...[
        Icon(
          _testResult!.success ? Icons.check_circle_outline : Icons.error_outline,
          size: 14,
          color: _testResult!.success ? AppColors.accent : AppColors.red,
        ),
        const SizedBox(width: 4),
        resultText,
      ],
    ];
  }

  Widget _cardRow(BuildContext context, Color color) {
    return Row(
      children: [
        if (widget.selectionMode) ...[
          _selectionCheckbox(),
          const SizedBox(width: 10),
        ],
        // Host icon
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _osIcon(widget.host),
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
                  if (widget.host.protocol == HostProtocol.rdp) ...[
                    const SizedBox(width: 6),
                    const RdpBadge(),
                  ],
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
        ..._trailing(context),
      ],
    );
  }

  /// Single-line list row: dot/checkbox · small OS icon · label ·
  /// user@host[:port] · test result · hover actions.
  Widget _compactRow(BuildContext context, Color color) {
    final port = widget.host.port == 22 ? '' : ':${widget.host.port}';
    return Row(
      children: [
        if (widget.selectionMode)
          _selectionCheckbox()
        else
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(
              color: AppColors.red, // offline by default
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 10),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: _osIcon(widget.host, pad: 5, svg: 14, fallback: 13),
        ),
        const SizedBox(width: 10),
        // Fixed label column so rows align vertically.
        SizedBox(
          width: 220,
          child: Text(
            widget.host.label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.host.protocol == HostProtocol.rdp) ...[
          const SizedBox(width: 6),
          const RdpBadge(),
        ],
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${widget.host.username}@${widget.host.host}$port',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        ..._trailing(context, maxResultWidth: 260),
      ],
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

  void _showMenu(BuildContext context, Offset tapPosition) {
    final hostProvider = context.read<HostProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final isSsh = widget.host.protocol == HostProtocol.ssh;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromRect(
        tapPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        _menuItem('terminal', Icons.terminal, 'Connect', () => sessionProvider.connectAny(widget.host)),
        if (isSsh)
          _menuItem('sftp', Icons.folder_outlined, 'SFTP', () => _openSftp(context)),
        _menuItem('edit', Icons.edit_outlined, 'Edit', () => widget.onEditHost?.call(widget.host)),
        const PopupMenuDivider(),
        _menuItem('duplicate', Icons.copy_outlined, 'Duplicate', () => _duplicate(context, hostProvider)),
        _menuItem('copy_url', Icons.link_outlined, isSsh ? 'Copy SSH URL' : 'Copy RDP URL', () => _copyHostUrl(context)),
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

  Future<void> _copyHostUrl(BuildContext context) async {
    final scheme = widget.host.protocol == HostProtocol.rdp ? 'rdp' : 'ssh';
    final url = '$scheme://${widget.host.username}@${widget.host.host}:${widget.host.port}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${scheme.toUpperCase()} URL copied'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _duplicate(BuildContext context, HostProvider hostProvider) async {
    final copy = Host(
      label: '${widget.host.label} (copy)',
      host: widget.host.host,
      port: widget.host.port,
      username: widget.host.username,
      protocol: widget.host.protocol,
      domain: widget.host.domain,
      rdpSecurity: widget.host.rdpSecurity,
      authType: widget.host.authType,
      keyId: widget.host.keyId,
      group: widget.host.group,
      tags: List<String>.from(widget.host.tags),
      jumpHostIds: List<String>.from(widget.host.jumpHostIds),
      sftpMode: widget.host.sftpMode,
      sftpServerCommand: widget.host.sftpServerCommand,
    );
    await hostProvider.addHost(copy);
    if (!context.mounted) return;
    widget.onEditHost?.call(copy);
  }
  void _moveToGroup(BuildContext context, HostProvider hostProvider) {
    final groups = hostProvider.allHosts
        .map((h) => h.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    showDialog<void>(
      context: context,
      builder: (_) => _MoveToGroupDialog(
        host: widget.host,
        groups: groups,
        onSelect: (g) => hostProvider.updateHost(widget.host.copyWith(group: g)),
      ),
    );
  }
  void _export(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _ExportDialog(host: widget.host),
    );
  }

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

// ── Move to Group Dialog ──────────────────────────────────

class _MoveToGroupDialog extends StatelessWidget {
  final Host host;
  final List<String> groups;
  final void Function(String) onSelect;

  const _MoveToGroupDialog({
    required this.host,
    required this.groups,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final options = ['', ...groups]; // '' = No group
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Move to Group', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 280,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (_, i) {
            final g = options[i];
            final label = g.isEmpty ? 'No group' : g;
            final isCurrent = g == host.group;
            return ListTile(
              dense: true,
              title: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              trailing: isCurrent ? const Icon(Icons.check, size: 16, color: AppColors.textSecondary) : null,
              onTap: () {
                Navigator.of(context).pop();
                onSelect(g);
              },
            );
          },
        ),
      ),
    );
  }
}

// ── Export Dialog ─────────────────────────────────────────

class _ExportDialog extends StatefulWidget {
  final Host host;
  const _ExportDialog({required this.host});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _showSshConfig = true;

  String get _sshConfigText {
    final alias = widget.host.label.replaceAll(RegExp(r'\s+'), '-');
    return 'Host $alias\n'
        '    HostName ${widget.host.host}\n'
        '    User ${widget.host.username}\n'
        '    Port ${widget.host.port}';
  }

  String get _jsonText {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'label': widget.host.label,
      'host': widget.host.host,
      'port': widget.host.port,
      'username': widget.host.username,
      'authType': widget.host.authType.name,
      'group': widget.host.group,
      'tags': widget.host.tags,
    });
  }

  String get _currentText => _showSshConfig ? _sshConfigText : _jsonText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Export Host', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _formatTab('.ssh/config', selected: _showSshConfig, onTap: () => setState(() => _showSshConfig = true)),
                const SizedBox(width: 8),
                _formatTab('JSON', selected: !_showSshConfig, onTap: () => setState(() => _showSshConfig = false)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                _currentText,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _currentText));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
            );
          },
          child: const Text('Copy', style: TextStyle(color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  Widget _formatTab(String label, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? AppColors.border : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
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

class _FacetChipBar extends StatelessWidget {
  final List<String> facets;
  final String query;
  final void Function(String facet) onToggle;

  const _FacetChipBar({
    required this.facets,
    required this.query,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = HostQuery.parse(query);
    bool isActive(String facet) {
      final colon = facet.indexOf(':');
      if (colon <= 0) return false;
      final key = facet.substring(0, colon);
      final value = facet.substring(colon + 1);
      return parsed.facets[key]?.contains(value) ?? false;
    }
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: facets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final facet = facets[i];
          final on = isActive(facet);
          return GestureDetector(
            onTap: () => onToggle(facet),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: on ? AppColors.accent : AppColors.border),
              ),
              child: Text(
                facet,
                style: TextStyle(
                  color: on ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Test-only entry point to the private facet chip bar.
@visibleForTesting
Widget facetChipBarForTest({
  required List<String> facets,
  required String query,
  required void Function(String) onToggle,
}) =>
    _FacetChipBar(facets: facets, query: query, onToggle: onToggle);

/// Test-only entry point to the private compact host row.
@visibleForTesting
Widget hostListRowForTest({
  required Host host,
  bool selectionMode = false,
  bool selected = false,
  VoidCallback? onToggleSelect,
}) =>
    _HostCard(
      host: host,
      compact: true,
      selectionMode: selectionMode,
      selected: selected,
      onToggleSelect: onToggleSelect,
    );

/// Test-only entry point to the private sort dropdown button.
@visibleForTesting
Widget sortButtonForTest({
  required HostSortMode mode,
  required ValueChanged<HostSortMode> onChanged,
}) =>
    _SortBtn(mode: mode, onChanged: onChanged);

/// Test-only entry point to the private grid/list view toggle.
@visibleForTesting
Widget viewToggleForTest({
  required String viewMode,
  required ValueChanged<String> onChanged,
}) =>
    _ViewToggle(viewMode: viewMode, onChanged: onChanged);
