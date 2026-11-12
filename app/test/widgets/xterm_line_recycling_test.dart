// Once the scrollback is full, the xterm fork reuses the line that a line
// feed trims instead of allocating a new one. Reuse must stay invisible:
// anchors (selections, search highlights) on a trimmed line keep seeing it
// detached with its old content, and renderers keyed on BufferLine.version
// never mistake a reused line for its previous content.
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  Terminal fullTerminal() {
    // Buffers start at 80x24, so the scrollback must hold at least 24 lines.
    final t = Terminal(maxLines: 30);
    t.resize(20, 5);
    for (var i = 0; i < 40; i++) {
      t.write('line $i\r\n');
    }
    expect(t.buffer.lines.isFull, isTrue);
    return t;
  }

  test('a trimmed line holding an anchor is not reused', () {
    final t = fullTerminal();
    final anchor = t.buffer.createAnchor(0, 0);
    final anchored = anchor.line!;
    final text = anchored.getText();

    for (var i = 0; i < 5; i++) {
      t.write('more $i\r\n');
    }

    expect(anchor.attached, isFalse);
    expect(anchored.getText(), text);
    for (var i = 0; i < t.buffer.lines.length; i++) {
      expect(identical(t.buffer.lines[i], anchored), isFalse);
    }
  });

  test('a reused line is blank and has a new version', () {
    final t = fullTerminal();
    final oldest = t.buffer.lines[0];
    final version = oldest.version;
    expect(oldest.getText().trim(), isNotEmpty);

    t.write('\n'); // trims the oldest line and appends an empty one

    final appended = t.buffer.lines[t.buffer.lines.length - 1];
    expect(appended.getText().trim(), isEmpty);
    expect(appended.isWrapped, isFalse);
    expect(appended.length, t.viewWidth);
    expect(identical(appended, oldest), isTrue, reason: 'line was reused');
    expect(appended.version, isNot(version));
    expect(appended.attached, isTrue);
    expect(appended.index, t.buffer.lines.length - 1);
  });
}
