import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/bulk/bulk_action_bar.dart';

import '../helpers/ys_test_app.dart';

void main() {
  testWidgets('fires callbacks; actions disabled with empty selection',
      (tester) async {
    // The bar has many buttons — set a wide test surface so none overflow.
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fired = <String>[];
    Widget build(int count) => ysTestApp(
            BulkActionBar(
              selectedCount: count,
              onSelectAll: () => fired.add('all'),
              onClear: () => fired.add('clear'),
              onConnectAll: () => fired.add('connect'),
              onRunCommand: () => fired.add('run'),
              onPushFiles: () => fired.add('push'),
              onDone: () => fired.add('done'),
            ),
          );

    await tester.pumpWidget(build(0));
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.text('Connect all'));
    expect(fired, isEmpty); // disabled at 0
    await tester.pumpAndSettle();

    await tester.pumpWidget(build(3));
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.text('Connect all'));
    await tester.tap(find.text('Run command'));
    await tester.tap(find.text('Push files'));
    await tester.tap(find.text('Select all'));
    // DONE lives inside a SingleChildScrollView — ensure it is visible before tap.
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle(); // let button press timers finish
    expect(fired, ['connect', 'run', 'push', 'all', 'done']);
  });

  testWidgets('does not overflow at narrow window widths', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ysTestApp(BulkActionBar(
      selectedCount: 3,
      onSelectAll: () {},
      onClear: () {},
      onConnectAll: () {},
      onRunCommand: () {},
      onPushFiles: () {},
      onDone: () {},
    )));
    expect(tester.takeException(), isNull); // no RenderFlex overflow
  });
}
