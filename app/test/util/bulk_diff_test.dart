import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/bulk_diff.dart';

BulkHostResult _ok(String label, String stdout) => BulkHostResult(
      host: Host(label: label, host: '$label.example', username: 'u'),
      status: BulkHostStatus.success,
      exitCode: 0,
      stdout: stdout,
    );

BulkHostResult _failed(String label) => BulkHostResult(
      host: Host(label: label, host: '$label.example', username: 'u'),
      status: BulkHostStatus.failed,
      error: 'connection refused',
    );

void main() {
  group('groupByOutput', () {
    test('groups identical outputs, largest group first', () {
      final groups = groupByOutput([
        _ok('a', 'v1'),
        _ok('b', 'v2'),
        _ok('c', 'v1'),
        _ok('d', 'v1'),
      ]);
      expect(groups, hasLength(2));
      expect(groups[0].output, 'v1');
      expect(groups[0].hostLabels, ['a', 'c', 'd']);
      expect(groups[1].hostLabels, ['b']);
    });

    test('trailing whitespace does not split a group', () {
      final groups = groupByOutput([_ok('a', 'same\n'), _ok('b', 'same')]);
      expect(groups, hasLength(1));
      expect(groups[0].hostLabels, ['a', 'b']);
    });

    test('equal-sized groups keep first-seen order', () {
      final groups = groupByOutput([_ok('a', 'x'), _ok('b', 'y')]);
      expect(groups[0].output, 'x');
      expect(groups[1].output, 'y');
    });

    test('failed hosts are excluded', () {
      final groups = groupByOutput([_ok('a', 'x'), _failed('b')]);
      expect(groups, hasLength(1));
      expect(groups[0].hostLabels, ['a']);
    });

    test('empty outputs still group together', () {
      final groups = groupByOutput([_ok('a', ''), _ok('b', '')]);
      expect(groups, hasLength(1));
      expect(groups[0].size, 2);
    });
  });

  group('lineDiff', () {
    test('identical inputs are all same', () {
      final d = lineDiff('a\nb', 'a\nb');
      expect(d.every((l) => l.op == DiffOp.same), isTrue);
      expect(d, hasLength(2));
    });

    test('added line', () {
      final d = lineDiff('a\nc', 'a\nb\nc');
      expect(d.map((l) => (l.op, l.text)).toList(), [
        (DiffOp.same, 'a'),
        (DiffOp.added, 'b'),
        (DiffOp.same, 'c'),
      ]);
    });

    test('removed line', () {
      final d = lineDiff('a\nb\nc', 'a\nc');
      expect(d.map((l) => (l.op, l.text)).toList(), [
        (DiffOp.same, 'a'),
        (DiffOp.removed, 'b'),
        (DiffOp.same, 'c'),
      ]);
    });

    test('changed line becomes removed + added', () {
      final d = lineDiff('a\nold\nc', 'a\nnew\nc');
      expect(d.map((l) => (l.op, l.text)).toList(), [
        (DiffOp.same, 'a'),
        (DiffOp.removed, 'old'),
        (DiffOp.added, 'new'),
        (DiffOp.same, 'c'),
      ]);
    });

    test('empty vs content', () {
      expect(lineDiff('', 'a').single.op, DiffOp.added);
      expect(lineDiff('a', '').single.op, DiffOp.removed);
      expect(lineDiff('', ''), isEmpty);
    });
  });

  group('sideBySideRows', () {
    test('zips a removed run with the following added run', () {
      final rows = sideBySideRows(const [
        DiffLine(DiffOp.same, 'a'),
        DiffLine(DiffOp.removed, 'old1'),
        DiffLine(DiffOp.removed, 'old2'),
        DiffLine(DiffOp.added, 'new1'),
        DiffLine(DiffOp.same, 'z'),
      ]);
      expect(rows, hasLength(4));
      expect((rows[0].left!.text, rows[0].right!.text), ('a', 'a'));
      expect((rows[1].left!.text, rows[1].right!.text), ('old1', 'new1'));
      expect(rows[2].left!.text, 'old2');
      expect(rows[2].right, isNull);
      expect((rows[3].left!.text, rows[3].right!.text), ('z', 'z'));
    });

    test('pure-added block: left is null, right carries the text', () {
      final rows = sideBySideRows(const [DiffLine(DiffOp.added, 'x')]);
      expect(rows, hasLength(1));
      expect(rows[0].left, isNull);
      expect(rows[0].right!.text, 'x');
    });
  });

  group('lineDiff LCS cap', () {
    test('completely different 2001-line inputs fall back to all-removed then all-added', () {
      final a = List.generate(2001, (i) => 'a$i').join('\n');
      final b = List.generate(2001, (i) => 'b$i').join('\n');
      final d = lineDiff(a, b);
      expect(d, hasLength(4002));
      expect(d.take(2001).every((l) => l.op == DiffOp.removed), isTrue);
      expect(d.skip(2001).every((l) => l.op == DiffOp.added), isTrue);
    });
  });
}
