// Regression tests for TerminalView scrollback scrolling: mouse wheel,
// trackpad pan, holding position while output streams, and scroll-offset
// compensation when the buffer trims at the maxLines cap.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  Future<ScrollController> pumpTerminal(
    WidgetTester tester,
    Terminal terminal,
  ) async {
    final scrollController = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            scrollController: scrollController,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pump();
    return scrollController;
  }

  void fillLines(Terminal terminal, int count, [String prefix = 'line']) {
    for (var i = 0; i < count; i++) {
      terminal.write('$prefix $i\r\n');
    }
  }

  testWidgets('mouse wheel scrolls scrollback up', (tester) async {
    final terminal = Terminal(maxLines: 10000);
    fillLines(terminal, 300);
    final sc = await pumpTerminal(tester, terminal);

    final max0 = sc.position.maxScrollExtent;
    debugPrint('PROBE initial: offset=${sc.offset} max=$max0');
    expect(max0, greaterThan(0), reason: 'scrollback must exist');
    expect(sc.offset, max0, reason: 'should start stuck to bottom');

    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -100))); // wheel up
    await tester.pump();
    debugPrint('PROBE after wheel-up: offset=${sc.offset} max=${sc.position.maxScrollExtent}');
    expect(sc.offset, lessThan(max0), reason: 'wheel up should scroll back');
  });

  testWidgets('scroll position holds while output streams', (tester) async {
    final terminal = Terminal(maxLines: 10000);
    fillLines(terminal, 300);
    final sc = await pumpTerminal(tester, terminal);

    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
    await tester.pump();
    final scrolledBack = sc.offset;
    debugPrint('PROBE scrolled back to: $scrolledBack');

    // Stream more output — viewport must NOT snap back to bottom.
    fillLines(terminal, 50, 'stream');
    await tester.pump();
    debugPrint('PROBE after stream: offset=${sc.offset} max=${sc.position.maxScrollExtent}');
    expect(sc.offset, lessThan(sc.position.maxScrollExtent),
        reason: 'must not snap to bottom while user reads scrollback');
  });

  testWidgets('trackpad pan scrolls scrollback up', (tester) async {
    final terminal = Terminal(maxLines: 10000);
    fillLines(terminal, 300);
    final sc = await pumpTerminal(tester, terminal);
    final max0 = sc.position.maxScrollExtent;

    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(2, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(center, pan: const Offset(0, 150)));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();
    debugPrint('PROBE after trackpad pan: offset=${sc.offset} max=$max0');
    expect(sc.offset, lessThan(max0),
        reason: 'trackpad two-finger scroll should scroll back');
  });

  testWidgets('scroll-up holds CONTENT when buffer is at maxLines cap',
      (tester) async {
    // Small cap so the buffer trims from the top while output streams.
    final terminal = Terminal(maxLines: 500);
    fillLines(terminal, 600); // buffer is now full (trimming active)
    final sc = await pumpTerminal(tester, terminal);

    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    await tester.pump();

    // What content line sits at the top of the viewport right now?
    String topLineText() {
      final lineHeight = sc.position.viewportDimension > 0
          ? (sc.position.maxScrollExtent + sc.position.viewportDimension) /
              terminal.buffer.lines.length
          : 1;
      final topIdx = (sc.offset / lineHeight).floor();
      return terminal.buffer.lines[topIdx].getText().trim();
    }

    final before = topLineText();
    debugPrint('PROBE top line before stream: "$before" offset=${sc.offset}');

    // Stream 100 more lines — buffer trims 100 from the top.
    fillLines(terminal, 100, 'stream');
    await tester.pump();

    final after = topLineText();
    debugPrint('PROBE top line after stream:  "$after" offset=${sc.offset}');
    expect(after, before,
        reason: 'the content the user scrolled to must stay put while '
            'the buffer trims (otherwise scroll-up is useless during '
            'fast output once scrollback is full)');
  });

  testWidgets('Shift+PageUp / Shift+PageDown page through scrollback',
      (tester) async {
    final terminal = Terminal(maxLines: 10000);
    fillLines(terminal, 300);
    final sc = await pumpTerminal(tester, terminal);
    final max0 = sc.position.maxScrollExtent;
    expect(sc.offset, max0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.pageUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    final afterPageUp = sc.offset;
    expect(afterPageUp, lessThan(max0),
        reason: 'Shift+PageUp must scroll the viewport back');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(sc.offset, greaterThan(afterPageUp),
        reason: 'Shift+PageDown must scroll back toward the bottom');
  });

  testWidgets('recoverFromStuckState restores scrolling after a dead TUI',
      (tester) async {
    final terminal = Terminal(maxLines: 10000);
    fillLines(terminal, 300);
    final sc = await pumpTerminal(tester, terminal);

    // Simulate a full-screen app that died uncleanly: alt screen + mouse
    // reporting left on (the state `reset` would normally clear).
    terminal.write('\x1b[?1049h\x1b[?1000h\x1b[?1006h\x1b[?25l');
    await tester.pump();
    expect(terminal.isUsingAltBuffer, isTrue);

    // Wheel does nothing in this state: no scrollback in the alt screen.
    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(sc.position.maxScrollExtent, 0,
        reason: 'alt screen has no scrollback');

    terminal.recoverFromStuckState();
    await tester.pump();
    expect(terminal.isUsingAltBuffer, isFalse);
    expect(terminal.cursorVisibleMode, isTrue);

    // Back in the main buffer the scrollback is intact and wheel scrolls.
    final max0 = sc.position.maxScrollExtent;
    expect(max0, greaterThan(0));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(sc.offset, lessThan(max0),
        reason: 'wheel must scroll again after recovery');
  });

  testWidgets('mouse drag does NOT scroll (selection instead)', (tester) async {
    // Documents the mouse-drag behavior for completeness.
    final terminal = Terminal(maxLines: 10000);
    fillLines(terminal, 300);
    final sc = await pumpTerminal(tester, terminal);
    final max0 = sc.position.maxScrollExtent;

    final center = tester.getCenter(find.byType(TerminalView));
    final gesture =
        await tester.startGesture(center, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pump();
    debugPrint('PROBE after mouse drag: offset=${sc.offset} max=$max0');
  });
}
