import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/accessory_bar_controller.dart';
import 'package:yourssh/mobile/terminal/accessory_key_bar.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  required AccessoryBarController controller,
  void Function(TerminalKey, {bool ctrl, bool alt})? onKey,
  void Function(String)? onText,
  VoidCallback? onOpenPanel,
}) async {
  await tester.pumpWidget(ysTestApp(
    AccessoryKeyBar(
      controller: controller,
      onKey: onKey ?? (k, {ctrl = false, alt = false}) {},
      onText: onText ?? (_) {},
      onOpenPanel: onOpenPanel,
    ),
    touch: true,
  ));
}

/// FButton starts a 100 ms press timer on tap; let it run out.
Future<void> _tap(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 150));
}

void main() {
  testWidgets('Esc taps emit the escape key', (tester) async {
    TerminalKey? got;
    await _pump(tester,
        controller: AccessoryBarController(),
        onKey: (k, {ctrl = false, alt = false}) => got = k);
    await _tap(tester, find.text('Esc'));
    expect(got, TerminalKey.escape);
  });

  testWidgets('Ctrl then arrow emits a ctrl-modified key', (tester) async {
    bool? gotCtrl;
    final c = AccessoryBarController();
    await _pump(tester,
        controller: c,
        onKey: (k, {ctrl = false, alt = false}) => gotCtrl = ctrl);
    await _tap(tester, find.text('Ctrl'));
    await tester.pump();
    await _tap(tester, find.byTooltip('Up'));
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
    await _tap(tester, find.text('^C'));
    expect(gotKey, TerminalKey.keyC);
    expect(gotCtrl, isTrue);
  });

  testWidgets('Esc/Tab/Ctrl render and Ctrl arms one-shot', (t) async {
    final c = AccessoryBarController();
    final keys = <(TerminalKey, bool)>[];
    await _pump(t,
        controller: c,
        onKey: (k, {ctrl = false, alt = false}) => keys.add((k, ctrl)));
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('Tab'), findsOneWidget);
    await _tap(t, find.text('Ctrl'));
    await t.pump();
    expect(c.ctrlArmed, isTrue);
    await _tap(t, find.text('Esc'));
    expect(keys.single, (TerminalKey.escape, true));
    expect(c.ctrlArmed, isFalse); // consumed
  });

  testWidgets('onOpenPanel button fires when provided', (t) async {
    var opened = false;
    await _pump(t,
        controller: AccessoryBarController(), onOpenPanel: () => opened = true);
    await _tap(t, find.byTooltip('Keyboard panel'));
    expect(opened, isTrue);
  });

  testWidgets('every key is an FButton with a >= 44 px hit target',
      (t) async {
    t.view.physicalSize = const Size(1400, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t,
        controller: AccessoryBarController(), onOpenPanel: () {});
    // panel + Esc Tab Ctrl Alt ^C ^D + 4 arrows + 6 symbols
    expect(find.byType(FButton), findsNWidgets(17));
    for (final e in find.byType(FButton).evaluate()) {
      final size = t.getSize(find.byWidget(e.widget));
      expect(size.height, greaterThanOrEqualTo(44), reason: '${e.widget}');
      expect(size.width, greaterThanOrEqualTo(44), reason: '${e.widget}');
    }
  });

  testWidgets('byte parity: exact keys / modifiers per button', (t) async {
    t.view.physicalSize = const Size(1400, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = AccessoryBarController();
    final keys = <(TerminalKey, bool, bool)>[];
    final texts = <String>[];
    await _pump(t,
        controller: c,
        onKey: (k, {ctrl = false, alt = false}) => keys.add((k, ctrl, alt)),
        onText: texts.add);
    Future<void> tapText(String s) async {
      await _tap(t, find.text(s));
      await t.pump();
    }

    await tapText('Esc');
    await tapText('Tab');
    await tapText('^C');
    await tapText('^D');
    for (final tip in ['Left', 'Up', 'Down', 'Right']) {
      await _tap(t, find.byTooltip(tip));
      await t.pump();
    }
    // Alt armed then plain key: alt latch consumed once.
    await tapText('Alt');
    expect(c.altArmed, isTrue);
    await tapText('Tab');
    expect(c.altArmed, isFalse);
    // Ctrl armed then a literal char: modifier consumed, text unchanged.
    await tapText('Ctrl');
    await tapText('/');
    expect(c.ctrlArmed, isFalse);
    for (final ch in ['-', '|', '~', ':', r'$']) {
      await tapText(ch);
    }
    expect(keys, [
      (TerminalKey.escape, false, false),
      (TerminalKey.tab, false, false),
      (TerminalKey.keyC, true, false),
      (TerminalKey.keyD, true, false),
      (TerminalKey.arrowLeft, false, false),
      (TerminalKey.arrowUp, false, false),
      (TerminalKey.arrowDown, false, false),
      (TerminalKey.arrowRight, false, false),
      (TerminalKey.tab, false, true),
    ]);
    expect(texts, ['/', '-', '|', '~', ':', r'$']);
  });

  testWidgets('armed modifier is visually distinct and re-tap disarms',
      (t) async {
    final c = AccessoryBarController();
    await _pump(t, controller: c);
    await _tap(t, find.text('Ctrl'));
    await t.pump();
    expect(c.ctrlArmed, isTrue);
  });

  testWidgets('every icon-only key has its tooltip', (t) async {
    t.view.physicalSize = const Size(1400, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _pump(t, controller: AccessoryBarController(), onOpenPanel: () {});
    for (final m in ['Keyboard panel', 'Left', 'Up', 'Down', 'Right']) {
      expect(find.byTooltip(m), findsOneWidget, reason: m);
    }
  });
}
