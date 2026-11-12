// Pre-existing xterm fork bugs: malformed escape sequences must never throw
// out of Terminal.write, scroll regions with a non-zero top margin must keep
// the buffer consistent, and a width change after the scrollback wrapped must
// keep the scrollback in order.
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('malformed sequences never throw', () {
    for (final seq in [
      '\x1b[1K',
      '\x1b[1J',
      '\x1b[38m',
      '\x1b[38;5m',
      '\x1b[38;2m',
      '\x1b[38;2;1m',
      '\x1b[38;2;1;2m',
      '\x1b[48m',
      '\x1b[48;5m',
      '\x1b[48;2;1m',
      '\x1b[1;38m',
      '\x1b[38;7m',
    ]) {
      test(seq.replaceAll('\x1b', 'ESC'), () {
        final t = Terminal();
        t.resize(80, 24);
        t.write('abc\r');
        expect(() => t.write(seq), returnsNormally);
        t.write('ok');
        expect(t.buffer.lines[t.buffer.scrollBack].getText().trimRight(),
            startsWith('ok'));
      });
    }

    test('truncated SGR still applies the params before it', () {
      final t = Terminal();
      t.write('\x1b[1;31;38;5m');
      expect(t.cursor.attrs & CellAttr.bold, isNot(0));
    });

    test('ESC[1K at column 0 leaves the line alone', () {
      final t = Terminal();
      t.write('abc\r\x1b[1K');
      expect(t.buffer.currentLine.getText().trimRight(), 'abc');
    });
  });

  group('scroll region with a non-zero top margin', () {
    void check(Terminal t) {
      final b = t.buffer;
      expect(b.lines.length, greaterThanOrEqualTo(t.viewHeight));
      for (var i = 0; i < b.lines.length; i++) {
        expect(b.lines[i].length, t.viewWidth);
        expect(b.lines[i].index, i, reason: 'line $i index');
      }
    }

    test('scroll up/down then insert/delete lines keeps every slot filled', () {
      final t = Terminal(maxLines: 100);
      t.resize(10, 8);
      for (var i = 0; i < 8; i++) {
        t.write('row$i${i < 7 ? '\r\n' : ''}');
      }
      t.write('\x1b[3;6r'); // margins rows 3..6
      t.write('\x1b[6;1H\n\n'); // scroll up inside the region
      t.write('\x1b[3;1H\x1bM\x1bM'); // reverse index: scroll down
      check(t);
      t.write('\x1b[4;1H\x1b[2L'); // insert lines
      check(t);
      t.write('\x1b[2M'); // delete lines
      t.write('\x1b[3L');
      check(t);
      final text = [
        for (var i = 0; i < t.buffer.lines.length; i++)
          t.buffer.lines[i].getText().trimRight()
      ];
      expect(text.length, 8);
    });

    test('scroll up moves the right lines', () {
      final t = Terminal(maxLines: 100);
      t.resize(10, 6);
      for (var i = 0; i < 6; i++) {
        t.write('r$i${i < 5 ? '\r\n' : ''}');
      }
      t.write('\x1b[2;5r\x1b[5;1H\n');
      final rows = [
        for (var i = 0; i < 6; i++) t.buffer.lines[i].getText().trimRight()
      ];
      expect(rows, ['r0', 'r2', 'r3', 'r4', '', 'r5']);
    });
  });

  group('width change after the scrollback wrapped', () {
    for (final cap in [30, 40]) {
      test('scrollback order survives a reflow (maxLines $cap)', () {
        final t = Terminal(maxLines: cap);
        t.resize(20, 5);
        for (var i = 0; i < 100; i++) {
          t.write('line$i\r\n');
        }
        t.resize(10, 5);
        final b = t.buffer;
        expect(b.lines.length, lessThanOrEqualTo(cap));
        final texts = <String>[];
        for (var i = 0; i < b.lines.length; i++) {
          texts.add(b.lines[i].getText().trimRight());
          expect(b.lines[i].index, i);
        }
        final nums = [
          for (final s in texts)
            if (s.startsWith('line')) int.parse(s.substring(4))
        ];
        expect(nums, isNotEmpty);
        for (var i = 1; i < nums.length; i++) {
          expect(nums[i], nums[i - 1] + 1, reason: texts.join('|'));
        }
        expect(nums.last, 99);
      });
    }
  });

  group('found by the fuzz test', () {
    test('DECRC after the screen shrank clamps the cursor', () {
      final t = Terminal();
      t.resize(80, 24);
      t.write('\x1b[20;70H\x1b7');
      t.resize(10, 5);
      expect(() => t.write('\x1b8x'), returnsNormally);
      expect(t.buffer.cursorY, lessThan(5));
    });

    test('DCH with the cursor in the pending-wrap column', () {
      final t = Terminal();
      t.resize(5, 3);
      t.write('abcde\x1b[P');
      expect(t.buffer.currentLine.getText().trimRight(), 'abcde');
    });

    test('reflow to one column drops wide chars instead of looping', () {
      final t = Terminal(maxLines: 50);
      t.resize(10, 4);
      t.write('日本語ab\r\nxyz');
      t.resize(1, 4);
      expect(t.buffer.lines.length, greaterThanOrEqualTo(4));
      for (var i = 0; i < t.buffer.lines.length; i++) {
        expect(t.buffer.lines[i].length, 1);
      }
    });

    test('growing height and width together keeps line widths', () {
      final t = Terminal(maxLines: 50);
      t.resize(10, 3);
      t.write('abcdefghij');
      t.resize(20, 8);
      for (var i = 0; i < t.buffer.lines.length; i++) {
        expect(t.buffer.lines[i].length, 20);
      }
      expect(t.buffer.lines[0].getText().trimRight(), 'abcdefghij');
    });

    test('scrollback keeps working after insert() wrapped the start index',
        () {
      final t = Terminal(maxLines: 30);
      t.resize(5, 3);
      for (var i = 0; i < 40; i++) {
        t.write('\x1b[1;2r\x1b[2;1H\n\x1b[r\n');
      }
      expect(t.buffer.lines.length, lessThanOrEqualTo(30));
    });

    test('clearing the scrollback keeps line indexes consistent', () {
      final t = Terminal(maxLines: 50);
      t.resize(5, 3);
      for (var i = 0; i < 10; i++) {
        t.write('l$i\r\n');
      }
      t.write('\x1b[3J');
      for (var i = 0; i < t.buffer.lines.length; i++) {
        expect(t.buffer.lines[i].index, i);
      }
    });
  });
}
