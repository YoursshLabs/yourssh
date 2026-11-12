import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('write notifies once per call by default', () {
    final t = Terminal();
    var n = 0;
    t.addListener(() => n++);
    t.write('a');
    t.write('b');
    expect(n, 2);
  });

  test('writeNoNotify parses without notifying; flushWrites notifies once', () {
    final t = Terminal();
    var n = 0;
    t.addListener(() => n++);
    t.writeNoNotify('hello');
    t.writeNoNotify(' world');
    expect(n, 0);
    expect(t.buffer.lines[0].toString().trimRight(), 'hello world');
    t.flushWrites();
    expect(n, 1);
    t.flushWrites(); // nothing dirty
    expect(n, 1);
  });

  test('mode 2026 suppresses repaint but keeps parsing; reset repaints', () {
    final t = Terminal();
    var n = 0;
    t.addListener(() => n++);
    t.write('\x1b[?2026h');
    final afterSet = n;
    t.write('frame1');
    t.write('\x1b[2J\x1b[Hframe2');
    expect(n, afterSet);
    expect(t.buffer.lines[0].toString().trimRight(), 'frame2');
    t.write('\x1b[?2026l');
    expect(n, afterSet + 1);
    t.write('x');
    expect(n, afterSet + 2);
  });

  test('mode 2026 safety timeout repaints after 150 ms', () {
    fakeAsync((async) {
      final t = Terminal();
      var n = 0;
      t.addListener(() => n++);
      t.write('\x1b[?2026h');
      final base = n;
      t.write('data');
      async.elapse(const Duration(milliseconds: 100));
      expect(n, base);
      async.elapse(const Duration(milliseconds: 60));
      expect(n, base + 1);
      // after the timeout the terminal paints normally again
      t.write('more');
      expect(n, base + 2);
    });
  });

  test('batched writes inside sync mode flush on reset', () {
    final t = Terminal();
    var n = 0;
    t.addListener(() => n++);
    t.writeNoNotify('\x1b[?2026hbody');
    t.flushWrites();
    expect(n, 0);
    t.writeNoNotify('\x1b[?2026l');
    t.flushWrites();
    expect(n, 1);
  });
}
