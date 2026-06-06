import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/bulk/bulk_action_bar.dart';

void main() {
  testWidgets('fires callbacks; actions disabled with empty selection',
      (tester) async {
    // The bar has many buttons — set a wide test surface so none overflow.
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fired = <String>[];
    Widget build(int count) => MaterialApp(
          home: Scaffold(
            body: BulkActionBar(
              selectedCount: count,
              onSelectAll: () => fired.add('all'),
              onClear: () => fired.add('clear'),
              onConnectAll: () => fired.add('connect'),
              onRunCommand: () => fired.add('run'),
              onPushFiles: () => fired.add('push'),
              onDone: () => fired.add('done'),
            ),
          ),
        );

    await tester.pumpWidget(build(0));
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.text('CONNECT ALL'));
    expect(fired, isEmpty); // disabled at 0

    await tester.pumpWidget(build(3));
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.text('CONNECT ALL'));
    await tester.tap(find.text('RUN COMMAND'));
    await tester.tap(find.text('PUSH FILES'));
    await tester.tap(find.text('SELECT ALL'));
    // DONE lives inside a SingleChildScrollView — ensure it is visible before tap.
    await tester.ensureVisible(find.text('DONE'));
    await tester.tap(find.text('DONE'));
    expect(fired, ['connect', 'run', 'push', 'all', 'done']);
  });

  testWidgets('does not overflow at narrow window widths', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BulkActionBar(
          selectedCount: 3,
          onSelectAll: () {},
          onClear: () {},
          onConnectAll: () {},
          onRunCommand: () {},
          onPushFiles: () {},
          onDone: () {},
        ),
      ),
    ));
    expect(tester.takeException(), isNull); // no RenderFlex overflow
  });
}
