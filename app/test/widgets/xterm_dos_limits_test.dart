// Remote output must not be able to freeze or exhaust the UI isolate through
// the xterm fork: huge resizes, huge REP counts, unterminated OSC/CSI
// sequences and overflowing numeric parameters are all bounded.
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  Terminal newTerminal() {
    final t = Terminal();
    t.resize(80, 25);
    return t;
  }

  String rowText(Terminal t, int row) =>
      t.buffer.lines[row].getText().trimRight();

  test('CSI 8 ; rows ; cols t is ignored (no remote-driven resize)', () {
    final t = newTerminal();
    t.write('\x1b[8;30000;30000t');
    expect(t.viewWidth, 80);
    expect(t.viewHeight, 25);
  });

  test('CSI n b with a huge count completes quickly', () {
    final t = newTerminal();
    final sw = Stopwatch()..start();
    t.write('a\x1b[100000000b');
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('unterminated OSC is dropped after the cap and parsing resumes', () {
    final t = newTerminal();
    t.write('\x1b]0;');
    final chunk = 'x' * 1024;
    for (var i = 0; i < 100; i++) {
      t.write(chunk); // 100 KiB, more than the 64 KiB cap
    }
    t.write('\r\nhello');
    expect(t.buffer.lines.toList().any((l) => l.getText().contains('hello')),
        isTrue);
  });

  test('unterminated CSI is dropped after the cap and parsing resumes', () {
    final t = newTerminal();
    t.write('\x1b[');
    t.write('1;' * 10000);
    t.write('\r\nhello');
    expect(t.buffer.lines.toList().any((l) => l.getText().contains('hello')),
        isTrue);
  });

  test('overflowing numeric parameter is clamped, not wrapped negative', () {
    final t = newTerminal();
    for (var i = 0; i < 5; i++) {
      t.write('line$i\r\n');
    }
    t.write('\x1b[H\x1b[9223372036854775808L');
    // Insert-lines far beyond the view pushes every line off screen.
    expect(rowText(t, 0), '');
    expect(t.viewHeight, 25);
  });
}
