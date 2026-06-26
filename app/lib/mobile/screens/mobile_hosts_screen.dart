import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/ssh_session.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import '../../util/host_query.dart';
import '../services/host_reachability_probe.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/host_card.dart';
import '../widgets/mobile_fab.dart';
import '../widgets/section_header.dart';
import '../widgets/status_dot.dart';
import '../widgets/tag_chip.dart';
import 'mobile_add_host_screen.dart';
import 'mobile_port_forward_screen.dart';
import 'mobile_sftp_screen.dart';
import 'mobile_terminal_screen.dart';

/// Hosts tab: header + search + folder chips + tag-grouped list + amber FAB.
/// Tap a host → connect via SessionProvider. Long-press → edit/delete sheet.
class MobileHostsScreen extends StatefulWidget {
  const MobileHostsScreen({super.key});

  @override
  State<MobileHostsScreen> createState() => _MobileHostsScreenState();
}

class _MobileHostsScreenState extends State<MobileHostsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _tagFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kickProbe());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _kickProbe() {
    if (!mounted) return;
    final all = context.read<HostProvider>().allHosts;
    context.read<HostReachabilityProbe>().probeAll(
          all.map((h) => (id: h.id, host: h.host, port: h.port)),
        );
  }

  /// Coarse connection state for a host, derived from any live session on it.
  HostConnState _stateFor(Host host, List<SshSession> sessions) {
    final mine = sessions.where((s) => s.host.id == host.id);
    if (mine.any((s) => s.status == SessionStatus.connected)) {
      return HostConnState.connected;
    }
    if (mine.any((s) => s.status == SessionStatus.connecting)) {
      return HostConnState.connecting;
    }
    return HostConnState.offline;
  }

  List<Host> _filtered(List<Host> all) {
    var hosts = all;
    final q = _query.trim();
    if (q.isNotEmpty) {
      hosts = hosts.where(HostQuery.parse(q).matches).toList();
    }
    if (_tagFilter != null) {
      hosts = hosts.where((h) => h.tags.contains(_tagFilter)).toList();
    }
    return hosts;
  }

  /// Groups hosts by their first tag (or "Other" if untagged).
  Map<String, List<Host>> _grouped(List<Host> hosts) {
    final map = <String, List<Host>>{};
    for (final h in hosts) {
      final key = h.tags.isNotEmpty ? h.tags.first : 'Other';
      map.putIfAbsent(key, () => []).add(h);
    }
    // Stable alphabetical order for sections.
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// Flat list of row descriptors for the grouped host list.
  /// Each entry is either a [_HeaderRow] (section title) or a [_HostRow].
  /// Built once per [build] — O(n) — so [ListView.builder] indexes O(1).
  List<_ListRow> _buildRows(Map<String, List<Host>> grouped) {
    final rows = <_ListRow>[];
    for (final entry in grouped.entries) {
      rows.add(_HeaderRow(entry.key));
      for (final host in entry.value) {
        rows.add(_HostRow(host));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<HostProvider>().allHosts;
    final sessions = context.watch<SessionProvider>().sshSessions;
    final probe = context.watch<HostReachabilityProbe>();

    final tags = <String>{for (final h in all) ...h.tags}.toList()..sort();
    final filtered = _filtered(all);
    final grouped = _grouped(filtered);
    final rows = _buildRows(grouped);

    // Online/total derived from probe states.
    final onlineCount = all
        .where((h) => probe.pingFor(h.id).state == HostReachState.online)
        .length;
    final totalCount = all.length;

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MobileTokens.space4,
                    MobileTokens.space4,
                    MobileTokens.space4,
                    MobileTokens.space2,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hosts',
                                style: mobileHeading(
                                    size: 30, weight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: MobileColors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$onlineCount online · $totalCount total',
                                  style: mobileBody(
                                    size: 13,
                                    color: MobileColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const _DecorativeCircle(icon: Icons.more_horiz),
                      const SizedBox(width: MobileTokens.space2),
                      const _DecorativeCircle(icon: Icons.person_outline),
                    ],
                  ),
                ),

                // ── Search field ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MobileTokens.space4,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    style: mobileBody(size: 15),
                    decoration: InputDecoration(
                      hintText: 'Search hosts, tags, IPs…',
                      hintStyle: mobileBody(
                          size: 15, color: MobileColors.textFaint),
                      prefixIcon: const Icon(Icons.search,
                          color: MobileColors.textFaint, size: 20),
                      filled: true,
                      fillColor: MobileColors.fieldFill,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: MobileTokens.space3),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(MobileTokens.radiusField),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(MobileTokens.radiusField),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(MobileTokens.radiusField),
                        borderSide: const BorderSide(
                            color: MobileColors.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: MobileTokens.space3),

                // ── Folder chips ─────────────────────────────────────────────
                if (tags.isNotEmpty)
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: MobileTokens.space4),
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(right: MobileTokens.space2),
                          child: TagChip(
                            label: 'All',
                            selected: _tagFilter == null,
                            onTap: () => setState(() => _tagFilter = null),
                          ),
                        ),
                        for (final tag in tags)
                          Padding(
                            padding: const EdgeInsets.only(
                                right: MobileTokens.space2),
                            child: TagChip(
                              label: tag,
                              selected: _tagFilter == tag,
                              onTap: () => setState(() =>
                                  _tagFilter = _tagFilter == tag ? null : tag),
                            ),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: MobileTokens.space2),

                // ── Host list ────────────────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyState(
                          onAdd: () => _pushAddHost(),
                          hasQuery: _query.isNotEmpty || _tagFilter != null,
                        )
                      : RefreshIndicator(
                          onRefresh: () async => _kickProbe(),
                          color: MobileColors.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(
                                bottom: MobileTokens.space4 * 4),
                            itemCount: rows.length,
                            itemBuilder: (_, i) =>
                                _buildRowWidget(rows[i], sessions, probe),
                          ),
                        ),
                ),
              ],
            ),

            // ── FAB ──────────────────────────────────────────────────────────
            Positioned(
              right: MobileTokens.space4,
              bottom: MobileTokens.space4,
              child: MobileFab(onTap: _pushAddHost),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grouped list helpers ─────────────────────────────────────────────────

  /// O(1) item builder — indexes into the pre-built flat [rows] list.
  Widget _buildRowWidget(
    _ListRow row,
    List<SshSession> sessions,
    HostReachabilityProbe probe,
  ) {
    if (row is _HeaderRow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          MobileTokens.space4,
          MobileTokens.space3,
          MobileTokens.space4,
          0,
        ),
        child: SectionHeader(row.title),
      );
    }
    final host = (row as _HostRow).host;
    final ping = probe.pingFor(host.id);
    final connState = _stateFor(host, sessions);
    return HostCard(
      host: host,
      online: connState == HostConnState.connected ||
          ping.state == HostReachState.online,
      connecting: connState == HostConnState.connecting ||
          ping.state == HostReachState.probing,
      latencyMs: ping.ms,
      onTap: () => _openSession(host),
      onLongPress: () => _showActions(host),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _openSession(Host host) async {
    final sp = context.read<SessionProvider>();

    // Re-entry: if a live session exists for this host, just open the terminal.
    final existing = sp.sshSessions
        .where((s) => s.host.id == host.id)
        .toList();
    if (existing.isNotEmpty) {
      final sessionId = existing.last.id;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => MobileTerminalScreen(
            focusSessionId: sessionId,
            onOpenFiles: (h) => _pushSftp(ctx, h),
            onOpenPortForward: (h) => _pushPortForward(ctx, h),
          ),
        ),
      );
      return;
    }

    // No live session — connect, then navigate.
    await sp.connectAny(host);
    if (!mounted) return;

    // After connectAny the session is in sshSessions; find the freshest one.
    final after = sp.sshSessions
        .where((s) => s.host.id == host.id)
        .toList();
    final sessionId = after.isNotEmpty ? after.last.id : null;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => MobileTerminalScreen(
          focusSessionId: sessionId,
          onOpenFiles: (h) => _pushSftp(ctx, h),
          onOpenPortForward: (h) => _pushPortForward(ctx, h),
        ),
      ),
    );
  }

  void _pushSftp(BuildContext ctx, Host host) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => MobileSftpScreen(host: host),
      ),
    );
  }

  void _pushPortForward(BuildContext ctx, Host host) {
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => MobilePortForwardScreen(host: host),
      ),
    );
  }

  void _pushAddHost() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MobileAddHostScreen()),
    );
  }

  Future<void> _showActions(Host host) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MobileColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: MobileTokens.space3),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MobileColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: MobileTokens.space2),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: MobileColors.textPrimary),
              title: Text('Edit',
                  style: mobileBody(size: 16, weight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MobileAddHostScreen(existing: host),
                ));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: MobileColors.red),
              title: Text('Delete',
                  style:
                      mobileBody(size: 16, color: MobileColors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(host);
              },
            ),
            const SizedBox(height: MobileTokens.space2),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Host host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MobileColors.surface,
        title: Text('Delete ${host.label}?',
            style: mobileHeading(size: 17)),
        content: Text(
          'This removes the saved host and its credentials.',
          style: mobileBody(size: 14, color: MobileColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: mobileBody(size: 15)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: mobileBody(size: 15, color: MobileColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HostProvider>().deleteHost(host.id);
    }
  }
}

// ── Flat-list row descriptors ─────────────────────────────────────────────────

sealed class _ListRow {}

/// A section-header row carrying the tag/title string.
final class _HeaderRow extends _ListRow {
  _HeaderRow(this.title);
  final String title;
}

/// A host row carrying the [Host] to render.
final class _HostRow extends _ListRow {
  _HostRow(this.host);
  final Host host;
}

// ── Helper widgets ────────────────────────────────────────────────────────────

/// Non-interactive decorative circle icon — purely visual, no tap target.
class _DecorativeCircle extends StatelessWidget {
  const _DecorativeCircle({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: MobileColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: MobileColors.border),
      ),
      child: Icon(icon, color: MobileColors.textMuted, size: 18),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.hasQuery});
  final VoidCallback onAdd;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.dns_outlined,
            size: 48,
            color: MobileColors.textFaint,
          ),
          const SizedBox(height: MobileTokens.space3),
          Text(
            hasQuery ? 'No results' : 'No hosts yet',
            style: mobileHeading(size: 17),
          ),
          const SizedBox(height: MobileTokens.space1),
          Text(
            hasQuery
                ? 'Try a different search term or tag'
                : 'Add a server to get started',
            style: mobileBody(size: 13, color: MobileColors.textMuted),
          ),
          if (!hasQuery) ...[
            const SizedBox(height: MobileTokens.space4),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add host'),
              style: FilledButton.styleFrom(
                  backgroundColor: MobileColors.accent,
                  foregroundColor: Colors.black),
            ),
          ],
        ],
      ),
    );
  }
}
