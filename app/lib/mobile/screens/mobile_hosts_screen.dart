import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/ssh_session.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../util/host_query.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/host_card.dart';
import '../widgets/status_dot.dart';
import '../widgets/tag_chip.dart';
import 'mobile_add_host_screen.dart';

/// Hosts tab: searchable list of saved hosts as Termius-style cards; tap to
/// connect, long-press for edit/delete actions, FAB to add. Tag chips filter
/// the list.
class MobileHostsScreen extends StatefulWidget {
  final VoidCallback onConnected;
  final VoidCallback onAddHost;

  const MobileHostsScreen({
    super.key,
    required this.onConnected,
    required this.onAddHost,
  });

  @override
  State<MobileHostsScreen> createState() => _MobileHostsScreenState();
}

class _MobileHostsScreenState extends State<MobileHostsScreen> {
  String _query = '';
  String? _tagFilter;

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

  @override
  Widget build(BuildContext context) {
    final all = context.watch<HostProvider>().allHosts;
    final sessions = context.watch<SessionProvider>().sshSessions;

    final tags = <String>{for (final h in all) ...h.tags}.toList()..sort();

    var hosts = all;
    final q = _query.trim();
    if (q.isNotEmpty) {
      hosts = hosts.where(HostQuery.parse(q).matches).toList();
    }
    if (_tagFilter != null) {
      hosts = hosts.where((h) => h.tags.contains(_tagFilter)).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: widget.onAddHost,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space3,
                MobileTokens.space3,
                MobileTokens.space3,
                MobileTokens.space2,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search hosts',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (tags.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space3),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: MobileTokens.space2),
                      child: TagChip(
                        label: 'All',
                        selected: _tagFilter == null,
                        onTap: () => setState(() => _tagFilter = null),
                      ),
                    ),
                    for (final tag in tags)
                      Padding(
                        padding: const EdgeInsets.only(right: MobileTokens.space2),
                        child: TagChip(
                          label: tag,
                          selected: _tagFilter == tag,
                          onTap: () => setState(
                              () => _tagFilter = _tagFilter == tag ? null : tag),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: hosts.isEmpty
                  ? _EmptyState(onAddHost: widget.onAddHost)
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                          top: MobileTokens.space2, bottom: 80),
                      itemCount: hosts.length,
                      itemBuilder: (_, i) {
                        final s = _stateFor(hosts[i], sessions);
                        return HostCard(
                          host: hosts[i],
                          online: s == HostConnState.connected,
                          connecting: s == HostConnState.connecting,
                          onTap: () => _connect(hosts[i]),
                          onLongPress: () => _showActions(hosts[i]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _connect(Host host) {
    context.read<SessionProvider>().connectAny(host);
    widget.onConnected();
  }

  /// Long-press action sheet: edit (opens the form pre-filled) or delete.
  Future<void> _showActions(Host host) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.edit_outlined, color: AppColors.textPrimary),
              title: const Text('Edit',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MobileAddHostScreen(existing: host),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text('Delete',
                  style: TextStyle(color: AppColors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(host);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Host host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete ${host.label}?',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: const Text('This removes the saved host and its credentials.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HostProvider>().deleteHost(host.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddHost;
  const _EmptyState({required this.onAddHost});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: MobileTokens.space3),
          const Text('No hosts yet',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          const SizedBox(height: MobileTokens.space1),
          const Text('Add a server to get started',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: MobileTokens.space4),
          FilledButton.icon(
            onPressed: onAddHost,
            icon: const Icon(Icons.add),
            label: const Text('Add host'),
          ),
        ],
      ),
    );
  }
}
