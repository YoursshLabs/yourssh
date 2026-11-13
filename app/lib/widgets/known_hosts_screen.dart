import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/known_host.dart';
import '../providers/known_hosts_provider.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'ys_form_controls.dart';
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
    return ColoredBox(
      color: YsColors.background,
      child: Column(
        children: [
          _TopBar(onImport: _importFromSystem),
          Expanded(
            child: provider.hosts.isEmpty
                ? const YsEmptyState(
                    icon: FLucideIcons.shieldCheck,
                    title: 'No known hosts yet',
                    message: 'Connect to a server to add one.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(YsSpace.s5),
                    itemCount: provider.hosts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: YsSpace.s2),
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
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
    decoration: const BoxDecoration(
      color: YsColors.sidebar,
      border: Border(bottom: BorderSide(color: YsColors.border)),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Known Hosts',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: YsColors.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FButton(
          variant: .outline,
          size: .sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.download),
          onPress: onImport,
          child: const Text('Import'),
        ),
      ],
    ),
  );
}

const _mono = TextStyle(
  fontFamily: kYsMonoFontFamily,
  fontFamilyFallback: kYsMonoFontFallback,
);

class _HostTile extends StatelessWidget {
  final KnownHost entry;
  const _HostTile({required this.entry});

  String _shortFp(String fp) {
    final parts = fp.split(':');
    if (parts.length <= 4) return fp;
    return '${parts.take(4).join(':')}…';
  }

  /// Removing a pinned key means the next connect trusts whatever key the
  /// server presents, so ask first. Cancel holds default focus.
  Future<void> _confirmRemove(BuildContext context, KnownHost entry) async {
    final provider = context.read<KnownHostsProvider>();
    final ok = await showYsConfirm(
      context,
      title: 'Remove host key?',
      message: 'YourSSH will trust whatever key ${entry.host}:${entry.port} '
          'presents on the next connection.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok) provider.remove(entry);
  }

  @override
  Widget build(BuildContext context) => settingsTileGroup(
    children: [
      FTile.raw(
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                '${entry.host}:${entry.port}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono.copyWith(
                  color: YsColors.foreground,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                entry.keyType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Tooltip(
                message: entry.fingerprint,
                child: Text(
                  _shortFp(entry.fingerprint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono.copyWith(
                    color: YsColors.mutedForeground,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            SettingsIconButton(
              icon: FLucideIcons.copy,
              tooltip: 'Copy fingerprint',
              onPress: () =>
                  Clipboard.setData(ClipboardData(text: entry.fingerprint)),
            ),
            const SizedBox(width: YsSpace.s2),
            SettingsIconButton(
              icon: FLucideIcons.trash2,
              tooltip: 'Remove',
              onPress: () => _confirmRemove(context, entry),
            ),
          ],
        ),
      ),
    ],
  );
}
