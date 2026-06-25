import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../util/host_query.dart';

/// Hosts tab: searchable list of saved hosts; tap to connect, FAB to add.
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

  @override
  Widget build(BuildContext context) {
    final all = context.watch<HostProvider>().allHosts;
    final q = _query.trim();
    // Reuse the dashboard's query engine so tag/facet search works on mobile too.
    final hosts = q.isEmpty ? all : all.where(HostQuery.parse(q).matches).toList();

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
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search hosts',
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: hosts.isEmpty
                  ? const Center(
                      child: Text('No hosts yet — tap + to add one',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.builder(
                      itemCount: hosts.length,
                      itemBuilder: (_, i) => _HostRow(
                        host: hosts[i],
                        onTap: () => _connect(hosts[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _connect(Host host) {
    // Fire the connect (async) and immediately switch to the Sessions tab so
    // the user watches it come up live.
    context.read<SessionProvider>().connectAny(host);
    widget.onConnected();
  }
}

class _HostRow extends StatelessWidget {
  final Host host;
  final VoidCallback onTap;
  const _HostRow({required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.dns_outlined, color: AppColors.textSecondary),
      title:
          Text(host.label, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text('${host.username}@${host.host}:${host.port}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
    );
  }
}
