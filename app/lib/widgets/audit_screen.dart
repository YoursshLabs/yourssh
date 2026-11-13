import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audit_event.dart';
import '../providers/audit_provider.dart';
import '../theme/app_theme.dart';
import '../util/time_format.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'confirm_dialog.dart';
import 'ys_form_controls.dart';

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
        child: Padding(
          padding: const EdgeInsets.all(YsSpace.s4),
          child: Text(
            'Audit log unavailable: ${provider.initError ?? 'not initialized'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: YsColors.mutedForeground, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(YsSpace.s4),
          child: Row(children: [
            const Expanded(
              child: Text('AUDIT LOG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: YsColors.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
            ),
            FButton(
              key: const ValueKey('audit-export-csv'),
              variant: .ghost,
              size: .sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.download),
              onPress: () => _export(context, csv: true),
              child: const Text('CSV'),
            ),
            const SizedBox(width: YsSpace.s1),
            FButton(
              key: const ValueKey('audit-export-json'),
              variant: .ghost,
              size: .sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.download),
              onPress: () => _export(context, csv: false),
              child: const Text('JSON'),
            ),
            const SizedBox(width: YsSpace.s1),
            FButton(
              key: const ValueKey('audit-clear'),
              variant: .destructive,
              size: .sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.trash2),
              onPress: () => _confirmClear(context),
              child: const Text('Clear'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
          child: Row(children: [
            // The value:null option ('All types') always matches, so the
            // select never shows a hint.
            SettingsSelect<String?>(
              key: const ValueKey('audit-type'),
              width: 140,
              value: provider.type,
              options: [
                (null, 'All types'),
                for (final t in AuditEventType.values) (t.name, t.name),
              ],
              onChanged: provider.setType,
            ),
            const SizedBox(width: YsSpace.s4),
            for (final (label, days) in const [
              ('Today', 1),
              ('7d', 7),
              ('30d', 30),
              ('All', 0)
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Semantics(
                  selected: provider.rangeDays == days,
                  button: true,
                  child: FButton(
                  key: ValueKey('audit-range-$days'),
                  variant: provider.rangeDays == days ? .primary : .outline,
                  size: .xs,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => provider.setRange(days),
                  child: Text(label),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: FTextField(
                key: const ValueKey('audit-search'),
                control: .managed(controller: _searchCtrl),
                size: .sm,
                hint: 'Search command or host…',
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                onSubmit: provider.setSearch,
                prefixBuilder: (context, style, variants) =>
                    FTextField.prefixIconBuilder(
                        context, style, variants, const Icon(FLucideIcons.search)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: YsSpace.s2),
        Expanded(
          child: provider.events.isEmpty
              ? const YsEmptyState(
                  icon: FLucideIcons.scrollText,
                  title: 'No audit events',
                )
              : ListView.builder(
                  itemCount:
                      provider.events.length + (provider.hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= provider.events.length) {
                      return Padding(
                        padding: const EdgeInsets.all(YsSpace.s2),
                        child: Center(
                          child: FButton(
                            key: const ValueKey('audit-load-more'),
                            variant: .outline,
                            size: .sm,
                            mainAxisSize: MainAxisSize.min,
                            onPress: provider.loadMore,
                            child: const Text('Load more'),
                          ),
                        ),
                      );
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

  YsStatus get _status => switch (event.type) {
        AuditEventType.connect => YsStatus.ok,
        AuditEventType.disconnect => YsStatus.warn,
        AuditEventType.exec => YsStatus.accent,
        AuditEventType.input => YsStatus.neutral,
      };

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
        fontFamily: kYsMonoFontFamily, fontFamilyFallback: kYsMonoFontFallback);
    final time = formatLocalTimestamp(event.ts);
    final source = event.meta['source'];
    final error = event.meta['error'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4, vertical: 6),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: YsColors.border, width: 0.5))),
      child: Row(children: [
        SizedBox(
            width: 150,
            child: Text(time,
                maxLines: 1,
                style: mono.copyWith(
                    color: YsColors.mutedForeground, fontSize: 11))),
        SizedBox(
          width: 84,
          child: Align(
            alignment: Alignment.centerLeft,
            child: YsStatusBadge(event.type.name, status: _status),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
            width: 160,
            child: Text(
                event.hostLabel == null
                    ? '—'
                    : '${event.username ?? ''}@${event.hostLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: YsColors.mutedForeground, fontSize: 12))),
        Expanded(
            child: Text(event.command ?? (error != null ? 'error: $error' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(
                    color: YsColors.foreground, fontSize: 12))),
        if (source != null)
          Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text('$source',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: YsColors.mutedForeground, fontSize: 11)),
              )),
        if (event.exitCode != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('exit ${event.exitCode}',
                maxLines: 1,
                style: mono.copyWith(
                    color: event.exitCode == 0 ? YsColors.ok : YsColors.error,
                    fontSize: 11)),
          ),
      ]),
    );
  }
}
