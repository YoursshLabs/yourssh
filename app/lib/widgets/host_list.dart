import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/session_provider.dart';
import '../services/sync_service.dart';
import 'add_host_dialog.dart';
import 'qr_export_dialog.dart';

class HostListPanel extends StatelessWidget {
  const HostListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final hostProvider = context.watch<HostProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final hosts = hostProvider.hosts;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: SearchBar(
            hintText: 'Search hosts...',
            leading: const Icon(Icons.search, size: 18),
            onChanged: hostProvider.setSearch,
            elevation: WidgetStateProperty.all(0),
            backgroundColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),

        // Host list
        Expanded(
          child: hosts.isEmpty
              ? const Center(
                  child: Text(
                    'No hosts yet\nAdd one with +',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: hosts.length,
                  itemBuilder: (ctx, i) => _HostTile(
                    host: hosts[i],
                    onConnect: () => sessionProvider.connect(hosts[i]),
                    onEdit: () => _editHost(ctx, hosts[i]),
                    onDelete: () => hostProvider.deleteHost(hosts[i].id),
                  ),
                ),
        ),

        // Bottom action bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Host'),
                  onPressed: () => _addHost(context),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.qr_code, size: 18),
                tooltip: 'Export via QR',
                onPressed: () => _showQrExport(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addHost(BuildContext context) async {
    final result = await showDialog<({Host host, String password})>(
      context: context,
      builder: (_) => const AddHostDialog(),
    );
    if (result == null || !context.mounted) return;
    await context.read<HostProvider>().addHost(
      result.host,
      password: result.password,
    );
  }

  Future<void> _editHost(BuildContext context, Host host) async {
    final result = await showDialog<({Host host, String password})>(
      context: context,
      builder: (_) => AddHostDialog(existing: host),
    );
    if (result == null || !context.mounted) return;
    await context.read<HostProvider>().updateHost(
      result.host,
      password: result.password,
    );
  }

  Future<void> _showQrExport(BuildContext context) async {
    final hostProvider = context.read<HostProvider>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrExportDialog(
        getPayload: () async {
          final hosts = hostProvider.allHosts;
          final passwords = await hostProvider.loadAllPasswords();
          return SyncService.buildPayload(hosts: hosts, passwords: passwords);
        },
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  final Host host;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HostTile({
    required this.host,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onDoubleTap: onConnect,
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: color.primaryContainer,
            child: Text(
              host.label[0].toUpperCase(),
              style: TextStyle(fontSize: 12, color: color.onPrimaryContainer),
            ),
          ),
          title: Text(
            host.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${host.username}@${host.host}:${host.port}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.terminal, size: 16),
                tooltip: 'Connect',
                onPressed: onConnect,
              ),
              PopupMenuButton(
                iconSize: 16,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
