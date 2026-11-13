import 'package:flutter/material.dart';

import '../../models/bulk_result.dart';
import '../../util/bulk_diff.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Diff tab of the bulk Run-command dialog: groups identical outputs
/// (largest group = default baseline), shows a unified diff of any group
/// against the baseline, and offers a two-host side-by-side compare.
class BulkDiffView extends StatefulWidget {
  final List<BulkHostResult> results;
  const BulkDiffView({super.key, required this.results});

  @override
  State<BulkDiffView> createState() => _BulkDiffViewState();
}

class _BulkDiffViewState extends State<BulkDiffView> {
  int _baseline = 0;
  int? _selected; // null → show baseline
  bool _compare = false;
  String? _hostAId;
  String? _hostBId;

  @override
  Widget build(BuildContext context) {
    final groups = groupByOutput(widget.results);
    final failed = widget.results
        .where((r) => r.status == BulkHostStatus.failed)
        .toList();
    if (groups.isEmpty) {
      return const Center(
        child: Text('No successful output to compare.',
            style: TextStyle(color: YsColors.mutedForeground, fontSize: 12)),
      );
    }
    // Normalize stale indices when a re-run produced fewer groups.
    if (_baseline >= groups.length) _baseline = 0;
    if (_selected != null && _selected! >= groups.length) _selected = null;
    final baseline = _baseline;
    final selected = _selected ?? baseline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(YsSpace.s3),
                child: Text(
                    '${groups.length} distinct output${groups.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: YsColors.foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < groups.length; i++)
                      _GroupTile(
                        group: groups[i],
                        isBaseline: i == baseline,
                        isSelected: i == selected && !_compare,
                        onTap: () =>
                            setState(() { _selected = i; _compare = false; }),
                        onSetBaseline: () => setState(() => _baseline = i),
                      ),
                    if (failed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                        child: Text('Failed (${failed.length})',
                            style: const TextStyle(
                                color: YsColors.error,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (final r in failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.host.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: YsColors.foreground,
                                      fontSize: 11)),
                              if (r.error != null)
                                Text(r.error!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: YsColors.mutedForeground,
                                        fontSize: 10)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(YsSpace.s2),
                child: FButton(
                  variant: .outline,
                  size: .sm,
                  onPress: () => setState(() => _compare = !_compare),
                  child: Flexible(
                    child: Text(
                        _compare ? 'Back to groups' : 'Compare two hosts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          ),
        ),
        const FDivider(axis: Axis.vertical),
        Expanded(
          child: _compare
              ? _HostCompare(
                  results: widget.results,
                  hostAId: _hostAId,
                  hostBId: _hostBId,
                  onPick: (a, b) => setState(() { _hostAId = a; _hostBId = b; }),
                )
              : selected == baseline
                  ? _PlainOutput(output: groups[baseline].output)
                  : _UnifiedDiff(
                      lines: lineDiff(
                          groups[baseline].output, groups[selected].output)),
        ),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  final OutputGroup group;
  final bool isBaseline;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onSetBaseline;
  const _GroupTile(
      {required this.group,
      required this.isBaseline,
      required this.isSelected,
      required this.onTap,
      required this.onSetBaseline});

  @override
  Widget build(BuildContext context) {
    final preview = group.hostLabels.take(3).join(', ') +
        (group.size > 3 ? ' +${group.size - 3}' : '');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: YsSpace.s2, vertical: 3),
        padding: const EdgeInsets.all(YsSpace.s3 - 2),
        decoration: BoxDecoration(
          color: isSelected ? YsColors.secondary : YsColors.card,
          borderRadius: BorderRadius.circular(YsRadius.control),
          border:
              Border.all(color: isSelected ? YsColors.primary : YsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${group.size} host${group.size == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: YsColors.foreground,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (isBaseline)
                  const YsStatusBadge('BASELINE', status: YsStatus.accent)
                else
                  Tooltip(
                    message: 'Set as baseline',
                    excludeFromSemantics: true,
                    child: FButton.icon(
                      variant: .ghost,
                      size: .xs,
                      semanticsLabel: 'Set as baseline',
                      onPress: onSetBaseline,
                      child: const Icon(FLucideIcons.flag),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: YsColors.mutedForeground, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _PlainOutput extends StatelessWidget {
  final String output;
  const _PlainOutput({required this.output});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(YsSpace.s3),
      child: SelectableText(output.isEmpty ? '(empty output)' : output,
          style: _mono(YsColors.foreground)),
    );
  }
}

class _UnifiedDiff extends StatelessWidget {
  final List<DiffLine> lines;
  const _UnifiedDiff({required this.lines});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final l = lines[i];
        final (prefix, color, bg) = switch (l.op) {
          DiffOp.added =>
            ('+ ', YsColors.ok, YsColors.ok.withValues(alpha: 0.08)),
          DiffOp.removed =>
            ('- ', YsColors.error, YsColors.error.withValues(alpha: 0.08)),
          DiffOp.same => ('  ', YsColors.mutedForeground, null),
        };
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('$prefix${l.text}', style: _mono(color)),
        );
      },
    );
  }
}

class _HostCompare extends StatelessWidget {
  final List<BulkHostResult> results;
  final String? hostAId;
  final String? hostBId;
  final void Function(String? a, String? b) onPick;
  const _HostCompare(
      {required this.results,
      required this.hostAId,
      required this.hostBId,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final ok =
        results.where((r) => r.status == BulkHostStatus.success).toList();
    final a = ok.where((r) => r.host.id == hostAId).firstOrNull;
    final b = ok.where((r) => r.host.id == hostBId).firstOrNull;

    Widget picker(String? value, bool isA) => SizedBox(
          width: 200,
          child: FSelect<String>.rich(
            // Stable key per side. The select is NOT re-created when the
            // options change; a stale pick (a re-run can drop hosts) is
            // handled by the `ok.any(...)` guard on `value` below.
            key: ValueKey(isA ? 'bulk-compare-a' : 'bulk-compare-b'),
            control: .lifted(
              value: ok.any((r) => r.host.id == value) ? value : null,
              onChange: (v) => onPick(isA ? v : hostAId, isA ? hostBId : v),
            ),
            format: (id) =>
                ok.firstWhere((r) => r.host.id == id).host.label,
            hint: isA ? 'Host A' : 'Host B',
            children: [
              for (final r in ok)
                FSelectItem<String>(
                    title: Text(r.host.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    value: r.host.id),
            ],
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(YsSpace.s2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                picker(hostAId, true),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: YsSpace.s3),
                  child: Icon(FLucideIcons.arrowLeftRight,
                      size: 16, color: YsColors.mutedForeground),
                ),
                picker(hostBId, false),
              ],
            ),
          ),
        ),
        Expanded(
          child: (a == null || b == null)
              ? const Center(
                  child: Text('Pick two hosts to compare.',
                      style: TextStyle(
                          color: YsColors.mutedForeground, fontSize: 12)))
              : _SideBySide(
                  rows: sideBySideRows(lineDiff(
                      a.stdout.trimRight(), b.stdout.trimRight()))),
        ),
      ],
    );
  }
}

class _SideBySide extends StatelessWidget {
  final List<({DiffLine? left, DiffLine? right})> rows;
  const _SideBySide({required this.rows});

  Widget _cell(DiffLine? line) {
    final color = switch (line?.op) {
      DiffOp.removed => YsColors.error,
      DiffOp.added => YsColors.ok,
      DiffOp.same => YsColors.mutedForeground,
      null => Colors.transparent,
    };
    final bg = switch (line?.op) {
      DiffOp.removed => YsColors.error.withValues(alpha: 0.08),
      DiffOp.added => YsColors.ok.withValues(alpha: 0.08),
      _ => null,
    };
    return Expanded(
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(line?.text ?? '', style: _mono(color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      itemBuilder: (_, i) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cell(rows[i].left),
            Container(width: 1, color: YsColors.border),
            _cell(rows[i].right),
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
    fontFamilyFallback: kYsMonoFontFallback);
