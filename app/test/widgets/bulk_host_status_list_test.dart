import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/bulk/bulk_host_status_list.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  final host = Host(label: 'web-1', host: 'w1.x', username: 'root');

  testWidgets('renders rows and expands to show output', (tester) async {
    await tester.pumpWidget(_wrap(BulkHostStatusList(results: [
      BulkHostResult(
          host: host,
          status: BulkHostStatus.success,
          exitCode: 0,
          stdout: 'Linux web-1',
          elapsed: const Duration(milliseconds: 1200)),
    ])));
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('1.2s'), findsOneWidget);
    expect(find.text('Linux web-1'), findsNothing); // collapsed

    await tester.tap(find.text('web-1'));
    await tester.pumpAndSettle();
    expect(find.text('Linux web-1'), findsOneWidget); // expanded
  });

  testWidgets('failed row shows error and non-zero exit shows chip',
      (tester) async {
    await tester.pumpWidget(_wrap(BulkHostStatusList(results: [
      BulkHostResult(
          host: host, status: BulkHostStatus.failed, error: 'auth failed'),
      BulkHostResult(
          host: Host(label: 'db-1', host: 'd1.x', username: 'root'),
          status: BulkHostStatus.success,
          exitCode: 2,
          stdout: ''),
    ])));
    expect(find.text('auth failed'), findsOneWidget); // error shown inline
    expect(find.text('exit 2'), findsOneWidget);
  });
}
