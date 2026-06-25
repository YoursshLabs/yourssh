import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/terminal_cursor_gestures.dart';

void main() {
  test('horizontal drag emits arrowRight per step', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(20, 0), [TerminalKey.arrowRight]);
    expect(m.addDelta(20, 0), [TerminalKey.arrowRight]);
  });

  test('negative vertical drag emits arrowUp', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(0, -20), [TerminalKey.arrowUp]);
  });

  test('sub-step deltas accumulate then fire once', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(0, 12), isEmpty);
    expect(m.addDelta(0, 12), [TerminalKey.arrowDown]);
  });

  test('dominant axis wins (no diagonal double-fire)', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(30, 5), [TerminalKey.arrowRight]);
  });

  test('reset clears accumulators and gear', () {
    final m = CursorDragMapper(baseStep: 20);
    m.addDelta(100, 0);
    m.reset();
    expect(m.addDelta(0, 19), isEmpty); // back to gear 1, sub-step
  });

  test('acceleration: step shrinks after sustained drag', () {
    final m = CursorDragMapper(baseStep: 20);
    // First burst pushes emitted count up into a higher gear.
    m.addDelta(200, 0); // many arrowRight
    // After gear-up, a 12px delta should now be enough to fire.
    final keys = m.addDelta(12, 0);
    expect(keys, isNotEmpty);
  });
}
