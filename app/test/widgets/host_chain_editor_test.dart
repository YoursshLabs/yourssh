import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/host_chain_editor.dart';

Host makeHost(String id, String label,
        {String user = 'root', String addr = '10.0.0.1', String? os}) =>
    Host(id: id, label: label, host: addr, username: user, detectedOs: os);

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );

void main() {
  testWidgets('empty chain shows helper text and Add a Host', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: const [],
      candidates: [makeHost('h1', 'bastion')],
      onChanged: (_) {},
    )));

    expect(find.text('Add a Host'), findsOneWidget);
    expect(find.textContaining('prod-db', findRichText: true), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('chain shows hops + destination, Add stays, Clear present',
      (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (_) {},
    )));

    expect(find.text('bastion'), findsOneWidget);
    expect(find.text('prod-db'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.text('Add a Host'), findsOneWidget); // append more
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('key icon on the last hop iff agentForwarding', (tester) async {
    final jump = makeHost('h1', 'bastion');
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [jump],
      agentForwarding: true,
      candidates: [jump],
      onChanged: (_) {},
    )));
    expect(find.byIcon(Icons.key), findsOneWidget);

    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [jump],
      agentForwarding: false,
      candidates: [jump],
      onChanged: (_) {},
    )));
    expect(find.byIcon(Icons.key), findsNothing);
  });

  testWidgets('appending a hop calls onChanged with both ids', (tester) async {
    List<String>? got;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (ids) => got = ids,
    )));

    await tester.tap(find.text('Add a Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b2'));
    await tester.pumpAndSettle();
    expect(got, ['h1', 'h2']);
  });

  testWidgets('picker excludes hosts already in the chain', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (_) {},
    )));

    await tester.tap(find.text('Add a Host'));
    await tester.pumpAndSettle();
    // h1 already a hop → only h2 (b2) offered.
    expect(find.text('b2'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('bastion')),
        findsNothing);
  });

  testWidgets('removing a hop fires onChanged without it', (tester) async {
    List<String>? got;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (ids) => got = ids,
    )));

    // Two remove buttons (one per hop); tap the first.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(got, ['h2']);
  });

  testWidgets('Clear empties the chain', (tester) async {
    List<String>? got;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion')],
      onChanged: (ids) => got = ids,
    )));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(got, isEmpty);
  });
}
