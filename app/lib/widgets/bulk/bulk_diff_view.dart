import 'package:flutter/material.dart';

import '../../models/bulk_result.dart';
import '../../theme/app_theme.dart';
import '../../util/bulk_diff.dart';

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
  String? _hostA;
  String? _hostB;

  @override
  Widget build(BuildContext context) {
    final groups = groupByOutput(widget.results);
    final failed = widget.results
        .where((r) => r.status == BulkHostStatus.failed)
        .toList();
    if (groups.isEmpty) {
      return const Center(
        child: Text('No successful output to compare.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    // Guard stale indices when a re-run produced fewer groups.
    final baseline = _baseline < groups.length ? _baseline : 0;
    final selected =
        (_selected != null && _selected! < groups.length) ? _selected! : baseline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    '${groups.length} distinct output${groups.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
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
                                color: AppColors.red,
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
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11)),
                              if (r.error != null)
                                Text(r.error!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 10)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: OutlinedButton(
                  onPressed: () => setState(() => _compare = !_compare),
                  child: Text(
                      _compare ? 'BACK TO GROUPS' : 'COMPARE TWO HOSTS',
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: _compare
              ? _HostCompare(
                  results: widget.results,
                  hostA: _hostA,
                  hostB: _hostB,
                  onPick: (a, b) => setState(() { _hostA = a; _hostB = b; }),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border),
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
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (isBaseline)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('BASELINE',
                        style: TextStyle(
                            color: AppColors.accent, fontSize: 9)),
                  )
                else
                  Tooltip(
                    message: 'Set as baseline',
                    child: InkWell(
                      onTap: onSetBaseline,
                      child: const Icon(Icons.flag_outlined,
                          size: 13, color: AppColors.textTertiary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
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
      padding: const EdgeInsets.all(12),
      child: SelectableText(output.isEmpty ? '(empty output)' : output,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace')),
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
          DiffOp.added => ('+ ', AppColors.accent,
              AppColors.accent.withValues(alpha: 0.08)),
          DiffOp.removed => ('- ', AppColors.red,
              AppColors.red.withValues(alpha: 0.08)),
          DiffOp.same => ('  ', AppColors.textSecondary, null),
        };
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('$prefix${l.text}',
              style: TextStyle(
                  color: color, fontSize: 12, fontFamily: 'monospace')),
        );
      },
    );
  }
}

class _HostCompare extends StatelessWidget {
  final List<BulkHostResult> results;
  final String? hostA;
  final String? hostB;
  final void Function(String? a, String? b) onPick;
  const _HostCompare(
      {required this.results,
      required this.hostA,
      required this.hostB,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final ok =
        results.where((r) => r.status == BulkHostStatus.success).toList();
    final labels = [for (final r in ok) r.host.label];
    final a = ok.where((r) => r.host.label == hostA).firstOrNull;
    final b = ok.where((r) => r.host.label == hostB).firstOrNull;

    DropdownButton<String> picker(String? value, bool isA) =>
        DropdownButton<String>(
          value: value,
          hint: Text(isA ? 'Host A' : 'Host B',
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12)),
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          items: [
            for (final l in labels)
              DropdownMenuItem(value: l, child: Text(l)),
          ],
          onChanged: (v) => onPick(isA ? v : hostA, isA ? hostB : v),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              picker(hostA, true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.compare_arrows,
                    size: 16, color: AppColors.textSecondary),
              ),
              picker(hostB, false),
            ],
          ),
        ),
        Expanded(
          child: (a == null || b == null)
              ? const Center(
                  child: Text('Pick two hosts to compare.',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12)))
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
      DiffOp.removed => AppColors.red,
      DiffOp.added => AppColors.accent,
      DiffOp.same => AppColors.textSecondary,
      null => Colors.transparent,
    };
    final bg = switch (line?.op) {
      DiffOp.removed => AppColors.red.withValues(alpha: 0.08),
      DiffOp.added => AppColors.accent.withValues(alpha: 0.08),
      _ => null,
    };
    return Expanded(
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(line?.text ?? '',
            style: TextStyle(
                color: color, fontSize: 12, fontFamily: 'monospace')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      itemBuilder: (_, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cell(rows[i].left),
          Container(width: 1, height: 16, color: AppColors.border),
          _cell(rows[i].right),
        ],
      ),
    );
  }
}
