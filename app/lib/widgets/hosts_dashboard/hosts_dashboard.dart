import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/app_session.dart';
import '../../models/host.dart';
import '../../models/rdp_session.dart';
import '../../models/ssh_key.dart';
import '../../models/ssh_session.dart';
import '../../models/vnc_session.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/os_detection.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../util/bulk_connect.dart';
import '../../util/host_query.dart';
import '../../util/host_sort.dart';
import '../bulk/bulk_action_bar.dart';
import '../confirm_delete_host.dart';
import '../bulk/bulk_push_dialog.dart';
import '../bulk/bulk_run_dialog.dart';
import '../protocol_badge.dart';
import '../server_monitor_sheet.dart';
import '../sftp_screen.dart';

part 'dashboard_dialogs.dart';
part 'empty_state.dart';
part 'facet_chip_bar.dart';
part 'group_card.dart';
part 'host_card.dart';
part 'host_grid.dart';
part 'host_list.dart';
part 'top_bar.dart';

class HostsDashboard extends StatefulWidget {
  final VoidCallback? onAddHost;
  final void Function(Host)? onEditHost;
  final VoidCallback? onOpenLocalTerminal;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  final VoidCallback? onDiscover;
  const HostsDashboard({super.key, this.onAddHost, this.onEditHost, this.onOpenLocalTerminal, this.onNewGroup, this.onImport, this.onDiscover});

  @override
  State<HostsDashboard> createState() => _HostsDashboardState();
}

class _HostsDashboardState extends State<HostsDashboard> {
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  bool _selectionMode = false;
  final Set<String> _selectedHostIds = {};

  // Memoized sort. Re-sorting the whole host list on every search keystroke is
  // wasteful, and sorting is independent of the query (filtering preserves
  // order). Cache the sorted list and reuse it until the host list or sort mode
  // changes — invalidated by a cheap per-element identity compare, since
  // HostProvider replaces Host objects (and the list) on every mutation.
  List<Host> _sortedCache = const [];
  List<Host>? _sortedInput;
  HostSortMode? _sortedMode;

  List<Host> _memoSortedHosts(List<Host> hosts, HostSortMode mode) {
    final prev = _sortedInput;
    final unchanged = prev != null &&
        _sortedMode == mode &&
        prev.length == hosts.length &&
        _identicalElements(prev, hosts);
    if (unchanged) return _sortedCache;
    _sortedInput = hosts;
    _sortedMode = mode;
    _sortedCache = sortHosts(hosts, mode);
    return _sortedCache;
  }

  static bool _identicalElements(List<Host> a, List<Host> b) {
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

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
      // VNC tabs likewise — same dedup as RDP.
      for (final s in sessionProvider.sessions.whereType<VncSession>())
        if (s.status == VncSessionStatus.connecting ||
            s.status == VncSessionStatus.connected)
          s.host.id,
    };
    final plan =
        planConnectAll(selected: _selectedHosts(), liveHostIds: live);
    if (plan.toConnect.length > 5) {
      final ok = await showYsDialog<bool>(
        context,
        builder: (ctx) => YsDialog(
          title: 'Open ${plan.toConnect.length} tabs?',
          actions: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FButton(
              variant: FButtonVariant.primary,
              onPress: () => Navigator.pop(ctx, true),
              child: const Text('Open all'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    for (final h in plan.toConnect) {
      unawaited(sessionProvider.connectAny(h));
    }
    if (!mounted) return;
    AppSnack.info(
        context,
        plan.skipped > 0
            ? 'Opened ${plan.toConnect.length} tabs · ${plan.skipped} already connected'
            : 'Opened ${plan.toConnect.length} tabs');
    _exitSelectionMode();
  }

  /// Bulk run/push are SSH operations — RDP hosts can never accept them and
  /// would only pollute the results with guaranteed failures.
  List<Host> _selectedSshHosts(String action) {
    final hosts = _selectedHosts();
    final ssh = hosts.where((h) => h.protocol == HostProtocol.ssh).toList();
    final skipped = hosts.length - ssh.length;
    if (skipped > 0) {
      AppSnack.info(
          context, '$skipped non-SSH host(s) skipped — $action is SSH-only');
    }
    return ssh;
  }

  void _openBulkRun() {
    final hosts = _selectedSshHosts('Run command');
    if (hosts.isEmpty) return;
    showYsDialog(
      context,
      barrierDismissible: false,
      builder: (_) => BulkRunDialog(hosts: hosts),
    );
  }

  void _openBulkPush() {
    final hosts = _selectedSshHosts('Push files');
    if (hosts.isEmpty) return;
    showYsDialog(
      context,
      barrierDismissible: false,
      builder: (_) => BulkPushDialog(hosts: hosts),
    );
  }

  void _onSearch(String value) {
    // The forui field reports every value change (selection moves and our
    // own facet writes included); only a text change re-filters.
    if (value == _search) return;
    setState(() => _search = value);
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
    // Prune stale selections in O(n) via a Set (only when a selection exists).
    if (_selectedHostIds.isNotEmpty) {
      final liveIds = {for (final h in hosts) h.id};
      _selectedHostIds.removeWhere((id) => !liveIds.contains(id));
    }
    final query = HostQuery.parse(_search);
    final settings = context.watch<SettingsProvider>();
    final sessionStats = context.select<SessionProvider, _SessionStats>(
        (p) => _SessionStats.from(p.sessions));
    final sortMode = HostSortMode.fromKey(settings.dashboardSort);
    // Sort the full list once (memoized), then filter the sorted result — the
    // filter preserves order, so this avoids an O(n log n) re-sort per keystroke.
    final sortedAll = _memoSortedHosts(hosts, sortMode);
    final sorted =
        query.isEmpty ? sortedAll : sortedAll.where(query.matches).toList();
    final filtered = sorted;
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

    return ColoredBox(
      color: YsColors.background,
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
                  onSearch: _onSearch,
                  onAddHost: widget.onAddHost,
                  onLocalTerminal: widget.onOpenLocalTerminal,
                  onNewGroup: widget.onNewGroup,
                  onImport: widget.onImport,
                  onDiscover: widget.onDiscover,
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
              padding: const EdgeInsets.fromLTRB(
                  YsSpace.s5, YsSpace.s2, YsSpace.s5, YsSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterRow(
                    facets: facets,
                    query: _search,
                    onToggle: _toggleFacet,
                    filteredCount: filtered.length,
                    totalHosts: hosts.length,
                  ),
                  const SizedBox(height: YsSpace.s4),
                  if (_search.isEmpty) ...[
                    YsSectionHeader(
                      title: 'Groups',
                      trailing:
                          '${groups.length} group${groups.length == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: YsSpace.s2),
                    Wrap(
                      spacing: YsSpace.s3,
                      runSpacing: YsSpace.s3,
                      children: groups.entries.map((e) {
                        final isPinned = pinnedGroupsUpper.contains(e.key);
                        return _GroupCard(
                          name: e.key,
                          count: e.value.length,
                          onDelete: (isPinned && e.value.isEmpty)
                              ? () => context
                                  .read<HostProvider>()
                                  .removeGroup(e.key)
                              : null,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: YsSpace.s5),
                  ],
                  YsSectionHeader(
                    title: 'Hosts',
                    trailing: filtered.isEmpty && _search.isNotEmpty
                        ? 'No results'
                        : null,
                  ),
                  const SizedBox(height: YsSpace.s2),
                  if (filtered.isEmpty && _search.isEmpty)
                    _EmptyState(onAdd: widget.onAddHost ?? () {})
                  else if (listView)
                    _HostList(
                      hosts: sorted,
                      sessionStats: sessionStats,
                      onEditHost: widget.onEditHost,
                      selectionMode: _selectionMode,
                      selectedIds: _selectedHostIds,
                      onToggleSelect: _toggleSelected,
                    )
                  else
                    _HostGrid(
                      hosts: sorted,
                      sessionStats: sessionStats,
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

/// Per-host session facts the cards show, derived from [SessionProvider]:
/// open tab count, whether one is connected (status dot), and whether an SSH
/// tab is open (Monitor). Value-equal, so `context.select` rebuilds the
/// dashboard only when these change.
@immutable
class _SessionStats {
  final Map<String, int> open;
  final Set<String> live;
  final Set<String> ssh;

  const _SessionStats(this.open, this.live, this.ssh);

  static const empty = _SessionStats({}, {}, {});

  factory _SessionStats.from(List<AppSession> sessions) {
    final open = <String, int>{};
    final live = <String>{};
    final ssh = <String>{};
    for (final s in sessions) {
      final (Host? host, bool connected) = switch (s) {
        SshSession x => (x.host, x.status == SessionStatus.connected),
        RdpSession x => (x.host, x.status == RdpSessionStatus.connected),
        VncSession x => (x.host, x.status == VncSessionStatus.connected),
        _ => (null, false),
      };
      if (host == null) continue;
      open[host.id] = (open[host.id] ?? 0) + 1;
      if (connected) live.add(host.id);
      if (s is SshSession) ssh.add(host.id);
    }
    return _SessionStats(open, live, ssh);
  }

  @override
  bool operator ==(Object other) =>
      other is _SessionStats &&
      mapEquals(open, other.open) &&
      setEquals(live, other.live) &&
      setEquals(ssh, other.ssh);

  @override
  int get hashCode => Object.hash(open.length, live.length, ssh.length);
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
