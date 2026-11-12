import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sftp_transfer_item.dart';
import '../providers/sftp_transfer_provider.dart';

import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Docked, minimizable transfer-progress panel at the bottom of the
/// two-panel SFTP workspace. Non-modal: transfers run in
/// [SftpTransferProvider] regardless of what this panel shows, so the user
/// keeps browsing (and can queue more transfers) while a batch runs.
///
/// Replaces the old centered modal `SftpTransferDialog`.
/// Spec: docs/superpowers/specs/2026-06-04-sftp-transfer-panel-and-local-checkboxes-design.md
class SftpTransferPanel extends StatefulWidget {
  const SftpTransferPanel({super.key});

  @override
  State<SftpTransferPanel> createState() => _SftpTransferPanelState();
}

class _SftpTransferPanelState extends State<SftpTransferPanel> {
  bool _minimized = false;
  Timer? _autoHide;

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  void _cancelAutoHide() {
    _autoHide?.cancel();
    _autoHide = null;
  }

  void _scheduleAutoHide(SftpTransferProvider tp) {
    if (_autoHide != null) return;
    _autoHide = Timer(const Duration(seconds: 3), () {
      _autoHide = null;
      if (mounted) tp.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SftpTransferProvider>(
      builder: (context, tp, _) {
        if (tp.items.isEmpty) {
          _cancelAutoHide();
          return const SizedBox.shrink();
        }

        final finished = !tp.items.any(
          (i) =>
              i.status == TransferStatus.pending ||
              i.status == TransferStatus.inProgress,
        );
        final hasErrors = tp.items.any((i) => i.status == TransferStatus.error);

        if (finished && !hasErrors) {
          // Successful batches dismiss themselves; errors stay until the
          // user closes the panel.
          _scheduleAutoHide(tp);
        } else if (!finished) {
          // A new batch was appended while the hide was pending.
          _cancelAutoHide();
        }

        return Container(
          decoration: const BoxDecoration(
            color: YsColors.card,
            border: Border(top: BorderSide(color: YsColors.border)),
          ),
          child: _minimized
              ? _buildStrip(tp, finished)
              : _buildExpanded(tp, finished),
        );
      },
    );
  }

  /// Determinate bar; unknown progress (0) shows an empty track, as the old
  /// indeterminate bar had no value either.
  Widget _bar(double value, {Color? fill}) => FDeterminateProgress(
    value: value.clamp(0.0, 1.0),
    style: .delta(
      constraints: const BoxConstraints.tightFor(height: 4),
      fillDecoration: fill == null
          ? null
          : DecorationDelta.value(BoxDecoration(color: fill)),
    ),
  );

  // ── Minimized strip ───────────────────────────────────

  Widget _buildStrip(SftpTransferProvider tp, bool finished) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          const SizedBox(width: YsSpace.s3),
          Expanded(child: _bar(tp.overallProgress)),
          const SizedBox(width: YsSpace.s3),
          Text(
            '${tp.completedCount} / ${tp.totalCount} files',
            style: const TextStyle(
              color: YsColors.mutedForeground,
              fontSize: 11,
            ),
          ),
          _iconBtn(
            FLucideIcons.chevronUp,
            'Expand',
            () => setState(() => _minimized = false),
          ),
          _trailingAction(tp, finished, compact: true),
          const SizedBox(width: YsSpace.s1),
        ],
      ),
    );
  }

  // ── Expanded panel ────────────────────────────────────

  Widget _buildExpanded(SftpTransferProvider tp, bool finished) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            YsSpace.s3,
            YsSpace.s2,
            YsSpace.s1,
            2,
          ),
          child: Row(
            children: [
              const Icon(
                FLucideIcons.arrowLeftRight,
                size: 15,
                color: YsColors.primary,
              ),
              const SizedBox(width: YsSpace.s2),
              Expanded(
                child: Text(
                  '${finished ? 'Transferred' : 'Transferring'} '
                  '${tp.completedCount} / ${tp.totalCount} files',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _iconBtn(
                FLucideIcons.chevronDown,
                'Minimize',
                () => setState(() => _minimized = true),
              ),
              _trailingAction(tp, finished, compact: false),
              const SizedBox(width: YsSpace.s1),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            YsSpace.s3,
            2,
            YsSpace.s3,
            YsSpace.s2,
          ),
          child: _bar(tp.overallProgress),
        ),
        const Divider(color: YsColors.border, height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: tp.items.length,
            itemBuilder: (_, i) => _buildRow(tp.items[i]),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  /// Cancel while running; Close once everything settled.
  Widget _trailingAction(
    SftpTransferProvider tp,
    bool finished, {
    required bool compact,
  }) {
    if (finished) {
      return _iconBtn(FLucideIcons.x, 'Close', tp.clear);
    }
    if (compact) {
      return _iconBtn(FLucideIcons.circleStop, 'Cancel', tp.cancel);
    }
    return FButton(
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.xs,
      onPress: tp.cancel,
      child: const Text('Cancel'),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: FButton.icon(
        variant: FButtonVariant.ghost,
        size: FButtonSizeVariant.xs,
        semanticsLabel: tooltip,
        onPress: onTap,
        child: Icon(icon),
      ),
    );
  }

  Widget _buildRow(SftpTransferItem item) {
    final (icon, color) = switch (item.status) {
      TransferStatus.done => (FLucideIcons.circleCheck, AppColors.success),
      TransferStatus.skipped => (
        FLucideIcons.skipForward,
        YsColors.mutedForeground,
      ),
      TransferStatus.error => (FLucideIcons.circleAlert, YsColors.error),
      TransferStatus.inProgress => (
        FLucideIcons.arrowLeftRight,
        YsColors.primary,
      ),
      TransferStatus.pending => (FLucideIcons.circle, YsColors.off),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: Text(
              item.fileName,
              style: const TextStyle(color: YsColors.foreground, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          if (item.status == TransferStatus.inProgress)
            SizedBox(width: 72, child: _bar(item.progress))
          else
            Text(_label(item), style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  String _label(SftpTransferItem item) => switch (item.status) {
    TransferStatus.done => item.totalBytes > 0 ? _fmt(item.totalBytes) : 'done',
    TransferStatus.skipped => 'skipped',
    TransferStatus.error => 'error',
    TransferStatus.pending => 'pending',
    TransferStatus.inProgress => '',
  };

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
