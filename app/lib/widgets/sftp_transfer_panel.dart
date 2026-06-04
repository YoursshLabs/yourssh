import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sftp_transfer_item.dart';
import '../providers/sftp_transfer_provider.dart';

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

        final finished = !tp.items.any((i) =>
            i.status == TransferStatus.pending ||
            i.status == TransferStatus.inProgress);
        final hasErrors =
            tp.items.any((i) => i.status == TransferStatus.error);

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
            color: Color(0xFF161616),
            border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
          ),
          child: _minimized
              ? _buildStrip(tp, finished)
              : _buildExpanded(tp, finished),
        );
      },
    );
  }

  // ── Minimized strip ───────────────────────────────────

  Widget _buildStrip(SftpTransferProvider tp, bool finished) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: tp.overallProgress > 0 ? tp.overallProgress : null,
                color: const Color(0xFF22C55E),
                backgroundColor: const Color(0xFF252525),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${tp.completedCount} / ${tp.totalCount} files',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
          ),
          _iconBtn(Icons.keyboard_arrow_up, 'Expand',
              () => setState(() => _minimized = false)),
          _trailingAction(tp, finished, compact: true),
          const SizedBox(width: 4),
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
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 2),
          child: Row(
            children: [
              const Icon(Icons.swap_horiz, size: 15, color: Color(0xFF22C55E)),
              const SizedBox(width: 8),
              Text(
                '${finished ? 'Transferred' : 'Transferring'} '
                '${tp.completedCount} / ${tp.totalCount} files',
                style: const TextStyle(
                    color: Color(0xFFD4D4D4),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              _iconBtn(Icons.keyboard_arrow_down, 'Minimize',
                  () => setState(() => _minimized = true)),
              _trailingAction(tp, finished, compact: false),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: tp.overallProgress > 0 ? tp.overallProgress : null,
              color: const Color(0xFF22C55E),
              backgroundColor: const Color(0xFF252525),
              minHeight: 5,
            ),
          ),
        ),
        const Divider(color: Color(0xFF2A2A2A), height: 1),
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
  Widget _trailingAction(SftpTransferProvider tp, bool finished,
      {required bool compact}) {
    if (finished) {
      return _iconBtn(Icons.close, 'Close', tp.clear);
    }
    if (compact) {
      return _iconBtn(Icons.stop_circle_outlined, 'Cancel', tp.cancel);
    }
    return TextButton(
      onPressed: tp.cancel,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF888888),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Cancel', style: TextStyle(fontSize: 12)),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 16),
      color: const Color(0xFF888888),
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
      onPressed: onTap,
    );
  }

  Widget _buildRow(SftpTransferItem item) {
    final (icon, color) = switch (item.status) {
      TransferStatus.done => (Icons.check_circle_outline, const Color(0xFF22C55E)),
      TransferStatus.skipped => (Icons.skip_next, const Color(0xFF888888)),
      TransferStatus.error => (Icons.error_outline, const Color(0xFFEF4444)),
      TransferStatus.inProgress => (Icons.swap_horiz, const Color(0xFF60A5FA)),
      TransferStatus.pending => (Icons.radio_button_unchecked, const Color(0xFF444444)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.fileName,
                style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          if (item.status == TransferStatus.inProgress)
            SizedBox(
              width: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.progress > 0 ? item.progress : null,
                  color: const Color(0xFF60A5FA),
                  backgroundColor: const Color(0xFF252525),
                  minHeight: 4,
                ),
              ),
            )
          else
            Text(_label(item), style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  String _label(SftpTransferItem item) => switch (item.status) {
        TransferStatus.done =>
          item.totalBytes > 0 ? _fmt(item.totalBytes) : 'done',
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
