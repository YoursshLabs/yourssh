import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audit_event.dart';
import '../providers/audit_provider.dart';
import '../theme/app_theme.dart';
import '../util/time_format.dart';
import 'confirm_dialog.dart';

/// Audit-log viewer: newest-first event table with type/time/search
/// filters, CSV/JSON export of the filtered view, and clear-all.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Keep the search box in sync with the provider's persisted filter —
    // re-entering the screen must not show filtered rows with an empty box.
    _searchCtrl.text = context.read<AuditProvider>().search;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<AuditProvider>().refresh());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _export(BuildContext context, {required bool csv}) async {
    final provider = context.read<AuditProvider>();
    try {
      final location = await getSaveLocation(
          suggestedName: csv ? 'audit-export.csv' : 'audit-export.json');
      if (location == null) return;
      final content = csv ? provider.exportCsv() : provider.exportJson();
      await File(location.path).writeAsString(content);
      if (context.mounted) {
        AppSnack.success(context, 'Exported to ${location.path}');
      }
    } catch (e) {
      if (context.mounted) AppSnack.error(context, 'Export failed: $e');
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final provider = context.read<AuditProvider>();
    final ok = await showConfirmDialog(
      context,
      title: 'Clear audit log?',
      message: 'All recorded events will be deleted.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (ok) provider.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuditProvider>();

    if (!provider.isAvailable) {
      return Center(
        child: Text(
          'Audit log unavailable: ${provider.initError ?? 'not initialized'}',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Text('AUDIT LOG',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const Spacer(),
            TextButton.icon(
                onPressed: () => _export(context, csv: true),
                icon: const Icon(Icons.download, size: 14),
                label: const Text('CSV', style: TextStyle(fontSize: 12))),
            TextButton.icon(
                onPressed: () => _export(context, csv: false),
                icon: const Icon(Icons.download, size: 14),
                label: const Text('JSON', style: TextStyle(fontSize: 12))),
            TextButton.icon(
                onPressed: () => _confirmClear(context),
                icon: const Icon(Icons.delete_outline,
                    size: 14, color: Colors.red),
                label: const Text('Clear',
                    style: TextStyle(fontSize: 12, color: Colors.red))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            DropdownButton<String?>(
              value: provider.type,
              // No hint: the value:null item ('All types') always renders,
              // so a hint would be dead code suggesting fallback behavior.
              dropdownColor: AppColors.card,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem(value: null, child: Text('All types')),
                for (final t in AuditEventType.values)
                  DropdownMenuItem(value: t.name, child: Text(t.name)),
              ],
              onChanged: provider.setType,
            ),
            const SizedBox(width: 16),
            for (final (label, days) in const [
              ('Today', 1),
              ('7d', 7),
              ('30d', 30),
              ('All', 0)
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: provider.rangeDays == days,
                  onSelected: (_) => provider.setRange(days),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Search command or host…',
                  hintStyle:
                      TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  prefixIcon: Icon(Icons.search, size: 14),
                  isDense: true,
                ),
                onSubmitted: provider.setSearch,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: provider.events.isEmpty
              ? const Center(
                  child: Text('No audit events',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 13)))
              : ListView.builder(
                  itemCount:
                      provider.events.length + (provider.hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= provider.events.length) {
                      return TextButton(
                          onPressed: provider.loadMore,
                          child: const Text('Load more'));
                    }
                    return _AuditRow(event: provider.events[i]);
                  },
                ),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEvent event;
  const _AuditRow({required this.event});

  Color get _typeColor => switch (event.type) {
        AuditEventType.connect => Colors.green,
        AuditEventType.disconnect => Colors.orange,
        AuditEventType.exec => Colors.blue,
        AuditEventType.input => Colors.purple,
      };

  @override
  Widget build(BuildContext context) {
    final time = formatLocalTimestamp(event.ts);
    final source = event.meta['source'];
    final error = event.meta['error'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Row(children: [
        SizedBox(
            width: 150,
            child: Text(time,
                style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontFamily: 'monospace'))),
        Container(
          width: 84,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4)),
          child: Text(event.type.name,
              style: TextStyle(color: _typeColor, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        SizedBox(
            width: 160,
            child: Text(
                event.hostLabel == null
                    ? '—'
                    : '${event.username ?? ''}@${event.hostLabel}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))),
        Expanded(
            child: Text(event.command ?? (error != null ? 'error: $error' : ''),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace'))),
        if (source != null)
          Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('$source',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 11))),
        if (event.exitCode != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('exit ${event.exitCode}',
                style: TextStyle(
                    color: event.exitCode == 0 ? Colors.green : Colors.red,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
      ]),
    );
  }
}
