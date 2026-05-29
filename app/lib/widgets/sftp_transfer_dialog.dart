// app/lib/widgets/sftp_transfer_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sftp_transfer_item.dart';
import '../providers/sftp_transfer_provider.dart';

class SftpTransferDialog extends StatefulWidget {
  const SftpTransferDialog({super.key});

  @override
  State<SftpTransferDialog> createState() => _SftpTransferDialogState();
}

class _SftpTransferDialogState extends State<SftpTransferDialog> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<SftpTransferProvider>(
      builder: (context, tp, _) {
        final allDone = tp.totalCount > 0 && tp.completedCount == tp.totalCount;
        if (allDone && !_closing) {
          _closing = true;
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted && context.mounted) {
              Navigator.of(context).pop();
            }
          });
        }
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, tp),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: tp.overallProgress > 0 ? tp.overallProgress : null,
                      color: const Color(0xFF22C55E),
                      backgroundColor: const Color(0xFF252525),
                      minHeight: 6,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tp.items.length,
                    itemBuilder: (_, i) => _buildRow(tp.items[i]),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SftpTransferProvider tp) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, size: 15, color: Color(0xFF22C55E)),
          const SizedBox(width: 8),
          Text(
            'Transferring ${tp.completedCount} / ${tp.totalCount} files',
            style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton(
            onPressed: () { tp.cancel(); Navigator.of(context).pop(); },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF888888),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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
