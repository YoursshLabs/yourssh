import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Column(children: [child])));

void main() {
  group('host list row', () {
    testWidgets('shows label and user@host, hides default port', (tester) async {
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root'),
      )));
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('root@10.0.0.1'), findsOneWidget);
    });

    testWidgets('appends non-default port', (tester) async {
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root', port: 2222),
      )));
      expect(find.text('root@10.0.0.1:2222'), findsOneWidget);
    });

    testWidgets('no checkbox outside selection mode', (tester) async {
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root'),
      )));
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('selection mode shows checkbox and row tap toggles', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root'),
        selectionMode: true,
        onToggleSelect: () => toggled++,
      )));
      expect(find.byType(Checkbox), findsOneWidget);
      await tester.tap(find.text('Web'));
      expect(toggled, 1);
    });
  });
}
