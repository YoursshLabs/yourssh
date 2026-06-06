import 'package:flutter/material.dart';

import '../../models/bulk_result.dart';
import '../../theme/app_theme.dart';
import '../../util/bulk_format.dart';

/// Per-host rows shared by the Run-command and Push-files dialogs:
/// status icon, label, error/exit info, transfer progress; tap to expand
/// stdout/stderr/error.
class BulkHostStatusList extends StatelessWidget {
  final List<BulkHostResult> results;
  const BulkHostStatusList({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text('Nothing run yet.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _ResultRow(result: results[i]),
    );
  }
}

class _ResultRow extends StatefulWidget {
  final BulkHostResult result;
  const _ResultRow({required this.result});

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _expanded = false;

  bool get _expandable {
    final r = widget.result;
    return r.stdout.isNotEmpty || r.stderr.isNotEmpty || r.error != null;
  }

  Widget _statusIcon(BulkHostResult r) {
    switch (r.status) {
      case BulkHostStatus.pending:
        return const Icon(Icons.radio_button_unchecked,
            size: 14, color: AppColors.textTertiary);
      case BulkHostStatus.running:
        return const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textSecondary));
      case BulkHostStatus.success:
        final clean = (r.exitCode ?? 0) == 0;
        return Icon(clean ? Icons.check_circle_outline : Icons.error_outline,
            size: 14, color: clean ? AppColors.accent : AppColors.orange);
      case BulkHostStatus.failed:
        return const Icon(Icons.error_outline,
            size: 14, color: AppColors.red);
      case BulkHostStatus.cancelled:
        return const Icon(Icons.block, size: 14, color: AppColors.textTertiary);
    }
  }

  String _elapsed(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final transferring =
        r.totalBytes > 0 && r.status == BulkHostStatus.running;
    return InkWell(
      onTap: _expandable ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusIcon(r),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.host.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      Text('${r.host.username}@${r.host.host}',
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ),
                if (r.error != null && !_expanded)
                  Flexible(
                    child: Text(r.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 11)),
                  ),
                if (r.status == BulkHostStatus.success &&
                    (r.exitCode ?? 0) != 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('exit ${r.exitCode}',
                        style: const TextStyle(
                            color: AppColors.orange, fontSize: 10)),
                  ),
                ],
                if (transferring) ...[
                  const SizedBox(width: 8),
                  Text('${formatByteSize(r.bytesTransferred)} / ${formatByteSize(r.totalBytes)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
                if (r.elapsed != null) ...[
                  const SizedBox(width: 8),
                  Text(_elapsed(r.elapsed!),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
                if (_expandable) ...[
                  const SizedBox(width: 6),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 14, color: AppColors.textTertiary),
                ],
              ],
            ),
            if (transferring) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: r.totalBytes == 0
                    ? null
                    : r.bytesTransferred / r.totalBytes,
                minHeight: 3,
                backgroundColor: AppColors.border,
                color: AppColors.accent,
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.stdout.isNotEmpty)
                      SelectableText(r.stdout.trimRight(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    if (r.stderr.isNotEmpty)
                      SelectableText(r.stderr.trimRight(),
                          style: const TextStyle(
                              color: AppColors.orange,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    if (r.error != null)
                      SelectableText(r.error!,
                          style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
