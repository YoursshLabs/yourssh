import 'package:flutter/material.dart';

import '../../models/bulk_result.dart';
import '../../util/bulk_format.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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
        child: Text(
          'Nothing run yet.',
          style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const FDivider(),
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
        return const Icon(
          FLucideIcons.circleDashed,
          size: 14,
          color: YsColors.off,
        );
      case BulkHostStatus.running:
        return const FCircularProgress(size: .xs);
      case BulkHostStatus.success:
        final clean = (r.exitCode ?? 0) == 0;
        return Icon(
          clean ? FLucideIcons.circleCheck : FLucideIcons.circleAlert,
          size: 14,
          color: clean ? YsColors.ok : YsColors.warn,
        );
      case BulkHostStatus.failed:
        return const Icon(
          FLucideIcons.circleAlert,
          size: 14,
          color: YsColors.error,
        );
      case BulkHostStatus.cancelled:
        return const Icon(FLucideIcons.ban, size: 14, color: YsColors.off);
    }
  }

  String _elapsed(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final transferring = r.totalBytes > 0 && r.status == BulkHostStatus.running;
    return InkWell(
      onTap: _expandable ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s4 - 2,
          vertical: YsSpace.s3 - 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 14, height: 14, child: _statusIcon(r)),
                const SizedBox(width: YsSpace.s3 - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.host.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: YsColors.foreground,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${r.host.username}@${r.host.host}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: YsColors.mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (r.error != null && !_expanded)
                  Flexible(
                    child: Text(
                      r.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: YsColors.error,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (r.status == BulkHostStatus.success &&
                    (r.exitCode ?? 0) != 0) ...[
                  const SizedBox(width: YsSpace.s2),
                  YsStatusBadge('exit ${r.exitCode}', status: YsStatus.warn),
                ],
                if (transferring) ...[
                  const SizedBox(width: YsSpace.s2),
                  Text(
                    '${formatByteSize(r.bytesTransferred)} / ${formatByteSize(r.totalBytes)}',
                    style: const TextStyle(
                      color: YsColors.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (r.elapsed != null) ...[
                  const SizedBox(width: YsSpace.s2),
                  Text(
                    _elapsed(r.elapsed!),
                    style: const TextStyle(
                      color: YsColors.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (_expandable) ...[
                  const SizedBox(width: YsSpace.s2 - 2),
                  Icon(
                    _expanded
                        ? FLucideIcons.chevronUp
                        : FLucideIcons.chevronDown,
                    size: 14,
                    color: YsColors.mutedForeground,
                  ),
                ],
              ],
            ),
            if (transferring) ...[
              const SizedBox(height: YsSpace.s2 - 2),
              FDeterminateProgress(value: r.bytesTransferred / r.totalBytes),
            ],
            if (_expanded) ...[
              const SizedBox(height: YsSpace.s2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(YsSpace.s3 - 2),
                decoration: BoxDecoration(
                  color: YsColors.background,
                  borderRadius: BorderRadius.circular(YsRadius.control),
                  border: Border.all(color: YsColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.stdout.isNotEmpty)
                      SelectableText(
                        r.stdout.trimRight(),
                        style: _mono(YsColors.foreground),
                      ),
                    if (r.stderr.isNotEmpty)
                      SelectableText(
                        r.stderr.trimRight(),
                        style: _mono(YsColors.warn),
                      ),
                    if (r.error != null)
                      SelectableText(r.error!, style: _mono(YsColors.error)),
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

TextStyle _mono(Color color) => TextStyle(
  color: color,
  fontSize: 12,
  fontFamily: kYsMonoFontFamily,
  fontFamilyFallback: kYsMonoFontFallback,
);
