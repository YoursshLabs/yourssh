// Pure helpers behind the bulk Run-command Diff tab. No Flutter/IO imports.
import 'dart:math';

import '../models/bulk_result.dart';

/// Hosts whose trimmed stdout was byte-identical.
class OutputGroup {
  final String output; // trimmed stdout shared by every host in the group
  final List<String> hostLabels; // display labels, in run order
  const OutputGroup({required this.output, required this.hostLabels});
  int get size => hostLabels.length;
}

/// Groups successful results by identical stdout (trailing whitespace
/// trimmed), largest group first; equal-sized groups keep first-seen order.
/// Failed/cancelled hosts never participate.
/// Only trailing whitespace is normalized; leading whitespace is significant.
List<OutputGroup> groupByOutput(List<BulkHostResult> results) {
  final labelsByOutput = <String, List<String>>{};
  final firstSeen = <String, int>{};
  for (final r in results) {
    if (r.status != BulkHostStatus.success) continue;
    final key = r.stdout.trimRight();
    firstSeen.putIfAbsent(key, () => firstSeen.length);
    (labelsByOutput[key] ??= []).add(r.host.label);
  }
  final keys = labelsByOutput.keys.toList()
    ..sort((a, b) {
      final bySize =
          labelsByOutput[b]!.length.compareTo(labelsByOutput[a]!.length);
      return bySize != 0 ? bySize : firstSeen[a]!.compareTo(firstSeen[b]!);
    });
  return [
    for (final k in keys)
      OutputGroup(output: k, hostLabels: labelsByOutput[k]!),
  ];
}

enum DiffOp { same, added, removed }

class DiffLine {
  final DiffOp op;
  final String text;
  const DiffLine(this.op, this.text);
}

/// LCS-table size cap. Common prefix/suffix are stripped first, so this only
/// trips on genuinely divergent huge outputs — those fall back to a plain
/// removed-everything/added-everything diff instead of an O(m·n) table.
const _maxLcsCells = 4 * 1000 * 1000;

/// Line-based diff from [a] to [b]: `removed` lines exist only in [a],
/// `added` only in [b].
List<DiffLine> lineDiff(String a, String b) {
  final aLines = a.isEmpty ? <String>[] : a.split('\n');
  final bLines = b.isEmpty ? <String>[] : b.split('\n');

  var start = 0;
  while (start < aLines.length &&
      start < bLines.length &&
      aLines[start] == bLines[start]) {
    start++;
  }
  var aEnd = aLines.length, bEnd = bLines.length;
  while (aEnd > start && bEnd > start && aLines[aEnd - 1] == bLines[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }

  return [
    for (var i = 0; i < start; i++) DiffLine(DiffOp.same, aLines[i]),
    ..._diffMiddle(aLines.sublist(start, aEnd), bLines.sublist(start, bEnd)),
    for (var i = aEnd; i < aLines.length; i++) DiffLine(DiffOp.same, aLines[i]),
  ];
}

List<DiffLine> _diffMiddle(List<String> a, List<String> b) {
  if (a.isEmpty) return [for (final l in b) DiffLine(DiffOp.added, l)];
  if (b.isEmpty) return [for (final l in a) DiffLine(DiffOp.removed, l)];
  if (a.length * b.length > _maxLcsCells) {
    return [
      for (final l in a) DiffLine(DiffOp.removed, l),
      for (final l in b) DiffLine(DiffOp.added, l),
    ];
  }
  final lcs =
      List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffOp.same, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffOp.removed, a[i]));
      i++;
    } else {
      out.add(DiffLine(DiffOp.added, b[j]));
      j++;
    }
  }
  while (i < a.length) {
    out.add(DiffLine(DiffOp.removed, a[i]));
    i++;
  }
  while (j < b.length) {
    out.add(DiffLine(DiffOp.added, b[j]));
    j++;
  }
  return out;
}

/// Pairs diff lines into side-by-side rows: a run of removed lines is
/// zipped with the added run that follows it (changed lines align), and
/// unmatched lines pair with null on the other side.
/// Expects the canonical [lineDiff] ordering: within a change block,
/// removed lines precede added lines.
List<({DiffLine? left, DiffLine? right})> sideBySideRows(
    List<DiffLine> lines) {
  final rows = <({DiffLine? left, DiffLine? right})>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].op == DiffOp.same) {
      rows.add((left: lines[i], right: lines[i]));
      i++;
      continue;
    }
    final removed = <DiffLine>[];
    final added = <DiffLine>[];
    while (i < lines.length && lines[i].op == DiffOp.removed) {
      removed.add(lines[i]);
      i++;
    }
    while (i < lines.length && lines[i].op == DiffOp.added) {
      added.add(lines[i]);
      i++;
    }
    final n = max(removed.length, added.length);
    for (var k = 0; k < n; k++) {
      rows.add((
        left: k < removed.length ? removed[k] : null,
        right: k < added.length ? added[k] : null,
      ));
    }
  }
  return rows;
}
