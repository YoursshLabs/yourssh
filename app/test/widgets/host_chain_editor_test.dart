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
  testWidgets('empty state shows helper text and Add a Host', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      candidates: [makeHost('h1', 'bastion')],
      onSelect: (_) {},
    )));

    expect(find.text('Add a Host'), findsOneWidget);
    expect(
      find.textContaining('prod-db', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('chain state shows both cards, arrow and Clear', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: makeHost('h1', 'bastion'),
      candidates: [makeHost('h1', 'bastion')],
      onSelect: (_) {},
    )));

    expect(find.text('bastion'), findsOneWidget);
    expect(find.text('prod-db'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Add a Host'), findsNothing);
  });

  testWidgets('key icon shows iff agentForwarding', (tester) async {
    final jump = makeHost('h1', 'bastion');
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: jump,
      agentForwarding: true,
      candidates: [jump],
      onSelect: (_) {},
    )));
    expect(find.byIcon(Icons.key), findsOneWidget);

    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: jump,
      agentForwarding: false,
      candidates: [jump],
      onSelect: (_) {},
    )));
    expect(find.byIcon(Icons.key), findsNothing);
  });

  testWidgets('Clear tap fires onSelect(null)', (tester) async {
    Host? selected = makeHost('sentinel', 's');
    var fired = false;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: makeHost('h1', 'bastion'),
      candidates: const [],
      onSelect: (h) {
        fired = true;
        selected = h;
      },
    )));

    await tester.tap(find.text('Clear'));
    expect(fired, isTrue);
    expect(selected, isNull);
  });

  testWidgets('picker filters by search and returns picked host',
      (tester) async {
    Host? selected;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      candidates: [
        makeHost('h1', 'bastion', addr: '10.0.0.1'),
        makeHost('h2', 'staging', addr: '10.0.0.2'),
      ],
      onSelect: (h) => selected = h,
    )));

    await tester.tap(find.text('Add a Host'));
    await tester.pumpAndSettle();

    expect(find.text('bastion'), findsOneWidget);
    expect(find.text('staging'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'stag');
    await tester.pumpAndSettle();
    expect(find.text('bastion'), findsNothing);
    expect(find.text('staging'), findsOneWidget);

    await tester.tap(find.text('staging'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'h2');
    expect(find.byType(Dialog), findsNothing);
  });
}
