import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/accessory_bar_controller.dart';
import 'package:yourssh/mobile/terminal/accessory_key_bar.dart';

Future<void> _pump(
  WidgetTester tester, {
  required AccessoryBarController controller,
  void Function(TerminalKey, {bool ctrl, bool alt})? onKey,
  void Function(String)? onText,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AccessoryKeyBar(
        controller: controller,
        onKey: onKey ?? (k, {ctrl = false, alt = false}) {},
        onText: onText ?? (_) {},
      ),
    ),
  ));
}

void main() {
  testWidgets('Esc taps emit the escape key', (tester) async {
    TerminalKey? got;
    await _pump(tester,
        controller: AccessoryBarController(),
        onKey: (k, {ctrl = false, alt = false}) => got = k);
    await tester.tap(find.text('Esc'));
    expect(got, TerminalKey.escape);
  });

  testWidgets('Ctrl then arrow emits a ctrl-modified key', (tester) async {
    bool? gotCtrl;
    final c = AccessoryBarController();
    await _pump(tester,
        controller: c,
        onKey: (k, {ctrl = false, alt = false}) => gotCtrl = ctrl);
    await tester.tap(find.text('Ctrl'));
    await tester.pump();
    await tester.tap(find.byTooltip('Up'));
    expect(gotCtrl, isTrue);
  });

  testWidgets('^C emits Ctrl+C directly', (tester) async {
    TerminalKey? gotKey;
    var gotCtrl = false;
    await _pump(tester,
        controller: AccessoryBarController(),
        onKey: (k, {ctrl = false, alt = false}) {
      gotKey = k;
      gotCtrl = ctrl;
    });
    await tester.tap(find.text('^C'));
    expect(gotKey, TerminalKey.keyC);
    expect(gotCtrl, isTrue);
  });

  testWidgets('Esc/Tab/Ctrl render and Ctrl arms one-shot', (t) async {
    final c = AccessoryBarController();
    final keys = <(TerminalKey, bool)>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccessoryKeyBar(
          controller: c,
          onKey: (k, {ctrl = false, alt = false}) => keys.add((k, ctrl)),
          onText: (_) {},
        ),
      ),
    ));
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('Tab'), findsOneWidget);
    await t.tap(find.text('Ctrl'));
    await t.pump();
    expect(c.ctrlArmed, isTrue);
    await t.tap(find.text('Esc'));
    expect(keys.single, (TerminalKey.escape, true));
    expect(c.ctrlArmed, isFalse); // consumed
  });

  testWidgets('onOpenPanel button fires when provided', (t) async {
    var opened = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccessoryKeyBar(
          controller: AccessoryBarController(),
          onKey: (k, {ctrl = false, alt = false}) {},
          onText: (_) {},
          onOpenPanel: () => opened = true,
        ),
      ),
    ));
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    expect(opened, isTrue);
  });
}
