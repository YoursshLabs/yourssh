import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/host_sort.dart';
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

  group('view toggle', () {
    testWidgets('reports mode on tap and highlights active side', (tester) async {
      String? changed;
      await tester.pumpWidget(_wrap(viewToggleForTest(
        viewMode: 'grid',
        onChanged: (v) => changed = v,
      )));
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.byIcon(Icons.view_list), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_list));
      expect(changed, 'list');

      await tester.tap(find.byIcon(Icons.grid_view));
      expect(changed, 'grid');
    });
  });

  group('sort button', () {
    testWidgets('shows current mode label', (tester) async {
      await tester.pumpWidget(_wrap(sortButtonForTest(
        mode: HostSortMode.nameAsc,
        onChanged: (_) {},
      )));
      expect(find.text('Name A→Z'), findsOneWidget);
    });

    testWidgets('opens menu and reports the picked mode', (tester) async {
      HostSortMode? picked;
      await tester.pumpWidget(_wrap(sortButtonForTest(
        mode: HostSortMode.nameAsc,
        onChanged: (m) => picked = m,
      )));
      await tester.tap(find.text('Name A→Z'));
      await tester.pumpAndSettle();
      expect(find.text('Newest first'), findsOneWidget);

      await tester.tap(find.text('Newest first'));
      await tester.pumpAndSettle();
      expect(picked, HostSortMode.createdDesc);
    });
  });
}
