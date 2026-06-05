import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/bulk/bulk_diff_view.dart';

BulkHostResult _ok(String label, String stdout) => BulkHostResult(
      host: Host(label: label, host: '$label.x', username: 'u'),
      status: BulkHostStatus.success,
      exitCode: 0,
      stdout: stdout,
    );

Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)));

void main() {
  testWidgets('groups outputs, baseline is the largest group',
      (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('a', 'kernel 6.1'),
      _ok('b', 'kernel 6.1'),
      _ok('c', 'kernel 5.4'),
    ])));
    expect(find.text('2 distinct outputs'), findsOneWidget);
    expect(find.text('BASELINE'), findsOneWidget);
    expect(find.text('2 hosts'), findsOneWidget);
    expect(find.text('1 host'), findsOneWidget);
  });

  testWidgets('selecting the divergent group shows a diff vs baseline',
      (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('a', 'kernel 6.1'),
      _ok('b', 'kernel 6.1'),
      _ok('c', 'kernel 5.4'),
    ])));
    await tester.tap(find.text('1 host'));
    await tester.pumpAndSettle();
    expect(find.text('- kernel 6.1'), findsOneWidget);
    expect(find.text('+ kernel 5.4'), findsOneWidget);
  });

  testWidgets('failed hosts listed separately', (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('a', 'x'),
      BulkHostResult(
          host: Host(label: 'bad', host: 'bad.x', username: 'u'),
          status: BulkHostStatus.failed,
          error: 'unreachable'),
    ])));
    expect(find.text('Failed (1)'), findsOneWidget);
    expect(find.text('bad'), findsOneWidget);
  });

  testWidgets('no successful results shows placeholder', (tester) async {
    await tester.pumpWidget(_wrap(const BulkDiffView(results: [])));
    expect(find.text('No successful output to compare.'), findsOneWidget);
  });

  testWidgets('compare mode tolerates duplicate host labels', (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('same-label', 'out-1'),
      _ok('same-label', 'out-2'),
    ])));
    await tester.tap(find.text('COMPARE TWO HOSTS'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
