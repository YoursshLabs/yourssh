import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../providers/audit_provider.dart';
import '../../providers/settings_provider.dart';
import '../confirm_dialog.dart';
import 'settings_tiles.dart';

/// Settings → Audit: retention and the destructive "Clear audit log".
class AuditSettingsSection extends StatelessWidget {
  const AuditSettingsSection({super.key});

  static const _retentionDays = [30, 90, 365, 0];

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Clear audit log?',
      message: 'All recorded events will be deleted.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      // Through the provider (not AuditService directly) so an open Audit
      // Log screen refreshes instead of showing stale deleted rows.
      context.read<AuditProvider>().clearAll();
    } on ProviderNotFoundException {
      // Settings pumped without audit wiring (tests).
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return SettingsSection(
      title: 'Audit',
      tiles: [
        settingsRowTile(
          label: 'Retention',
          description: 'Delete audit events older than this on launch',
          trailing: SettingsSelect<int>(
            key: const ValueKey('settings-audit-retention'),
            value: _retentionDays.contains(settings.auditRetentionDays)
                ? settings.auditRetentionDays
                : 90,
            options: [
              for (final d in _retentionDays)
                (d, d == 0 ? 'Keep forever' : '$d days'),
            ],
            onChanged: (d) =>
                context.read<SettingsProvider>().save(auditRetentionDays: d),
          ),
        ),
        settingsRowTile(
          label: 'Clear audit log',
          description: 'Delete all recorded events now',
          trailing: FButton(
            key: const ValueKey('settings-audit-clear'),
            variant: .destructive,
            size: .sm,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.trash2),
            onPress: () => _confirmClear(context),
            child: const Text('Clear'),
          ),
        ),
      ],
    );
  }
}
