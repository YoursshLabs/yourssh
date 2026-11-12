import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/known_host.dart';
import '../providers/known_hosts_provider.dart';
import '../theme/app_theme.dart';
import '../util/known_hosts_importer.dart';

class KnownHostsScreen extends StatefulWidget {
  const KnownHostsScreen({super.key});

  @override
  State<KnownHostsScreen> createState() => _KnownHostsScreenState();
}

class _KnownHostsScreenState extends State<KnownHostsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KnownHostsProvider>().load();
    });
  }

  Future<void> _importFromSystem() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final path = '$home/.ssh/known_hosts';
    final file = File(path);

    if (!await file.exists()) {
      if (!mounted) return;
      AppSnack.error(context, '~/.ssh/known_hosts not found');
      return;
    }

    final content = await file.readAsString();
    final parsed = KnownHostsImporter.parse(content);

    if (!mounted) return;
    final added = await context.read<KnownHostsProvider>().importHosts(parsed);

    if (!mounted) return;
    final msg = added > 0 ? 'Imported $added ${added == 1 ? 'entry' : 'entries'}' : 'No new entries found';
    AppSnack.info(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KnownHostsProvider>();
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _TopBar(onImport: _importFromSystem),
          Expanded(
            child: provider.hosts.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: provider.hosts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _HostTile(entry: provider.hosts[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onImport;
  const _TopBar({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Known Hosts',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: onImport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_outlined, size: 13, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Text('IMPORT',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('No known hosts yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text('Connect to a server to add one.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  final KnownHost entry;
  const _HostTile({required this.entry});

  String _shortFp(String fp) {
    final parts = fp.split(':');
    if (parts.length <= 4) return fp;
    return '${parts.take(4).join(':')}…';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text('${entry.host}:${entry.port}',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(entry.keyType,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: entry.fingerprint,
              child: Text(_shortFp(entry.fingerprint),
                  style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy,
                size: 14, color: AppColors.textTertiary),
            tooltip: 'Copy fingerprint',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: entry.fingerprint)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.textTertiary),
            tooltip: 'Remove',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => context.read<KnownHostsProvider>().remove(entry),
          ),
        ],
      ),
    );
  }
}
