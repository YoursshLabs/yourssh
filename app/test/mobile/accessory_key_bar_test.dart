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
}
