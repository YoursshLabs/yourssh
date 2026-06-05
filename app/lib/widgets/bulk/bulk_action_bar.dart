import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Replaces the hosts-dashboard top bar while selection mode is active.
class BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onConnectAll;
  final VoidCallback onRunCommand;
  final VoidCallback onPushFiles;
  final VoidCallback onDone;

  const BulkActionBar({
    super.key,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onClear,
    required this.onConnectAll,
    required this.onRunCommand,
    required this.onPushFiles,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text('$selectedCount selected',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          _BarBtn(label: 'SELECT ALL', onTap: onSelectAll),
          const SizedBox(width: 8),
          _BarBtn(label: 'CLEAR', onTap: onClear, enabled: hasSelection),
          const Spacer(),
          _BarBtn(
              icon: Icons.cable,
              label: 'CONNECT ALL',
              onTap: onConnectAll,
              enabled: hasSelection),
          const SizedBox(width: 8),
          _BarBtn(
              icon: Icons.terminal,
              label: 'RUN COMMAND',
              onTap: onRunCommand,
              enabled: hasSelection),
          const SizedBox(width: 8),
          _BarBtn(
              icon: Icons.upload_file,
              label: 'PUSH FILES',
              onTap: onPushFiles,
              enabled: hasSelection),
          const SizedBox(width: 16),
          _BarBtn(label: 'DONE', onTap: onDone, accent: true),
        ],
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool accent;
  const _BarBtn(
      {this.icon,
      required this.label,
      required this.onTap,
      this.enabled = true,
      this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textTertiary
        : accent
            ? AppColors.accent
            : AppColors.textSecondary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
              color: accent && enabled ? AppColors.accent : AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}
