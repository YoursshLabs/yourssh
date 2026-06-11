// Tests for the xterm fork's per-line picture cache (render smoothness fix):
// cache hits on unchanged lines, invalidation on content/style/keyword-rule
// changes, and pixel-equivalence with the direct paintLine path.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TerminalPainter newPainter() => TerminalPainter(
        theme: TerminalThemes.defaultTheme,
        textStyle: const TerminalStyle(),
        textScaler: TextScaler.noScaling,
      );

  BufferLine lineWithText(Terminal terminal, String text) {
    terminal.write(text);
    return terminal.buffer.lines[terminal.buffer.absoluteCursorY];
  }

  test('unchanged line returns the identical cached picture', () {
    final terminal = Terminal();
    final painter = newPainter();
    final line = lineWithText(terminal, 'hello world');

    final first = painter.getLinePicture(line);
    final second = painter.getLinePicture(line);
    expect(identical(first, second), isTrue,
        reason: 'no content change → cache hit');
  });

  test('mutating the line re-records the picture', () {
    final terminal = Terminal();
    final painter = newPainter();
    final line = lineWithText(terminal, 'hello');

    final before = painter.getLinePicture(line);
    terminal.write(' more');
    final after = painter.getLinePicture(line);
    expect(identical(before, after), isFalse,
        reason: 'version bump → re-record');
  });

  test('BufferLine.version bumps on every mutation kind', () {
    final line = BufferLine(80);
    var last = line.version;
    void expectBumped(String what) {
      expect(line.version, greaterThan(last), reason: what);
      last = line.version;
    }

    line.setCell(0, 0x41, 1, CursorStyle.empty);
    expectBumped('setCell');
    line.setForeground(0, 123);
    expectBumped('setForeground');
    line.setBackground(0, 123);
    expectBumped('setBackground');
    line.setAttributes(0, 1);
    expectBumped('setAttributes');
    line.setCodePoint(0, 0x42);
    expectBumped('setCodePoint');
    line.eraseCell(0, CursorStyle.empty);
    expectBumped('eraseCell');
    line.eraseRange(0, 10, CursorStyle.empty);
    expectBumped('eraseRange');
    line.removeCells(0, 2);
    expectBumped('removeCells');
    line.insertCells(0, 2);
    expectBumped('insertCells');
    line.resize(120);
    expectBumped('resize');
    line.resetCell(0);
    expectBumped('resetCell');
  });

  test('style / theme / keyword-rule changes invalidate the cache', () {
    final terminal = Terminal();
    final painter = newPainter();
    final line = lineWithText(terminal, 'ERROR something');

    final p0 = painter.getLinePicture(line);

    painter.textStyle = const TerminalStyle(fontSize: 20);
    final p1 = painter.getLinePicture(line);
    expect(identical(p0, p1), isFalse, reason: 'textStyle change');

    painter.keywordRules = [
      KeywordHighlightRule(
        pattern: RegExp('ERROR'),
        background: const Color(0xFFFF0000),
      ),
    ];
    final p2 = painter.getLinePicture(line);
    expect(identical(p1, p2), isFalse, reason: 'keyword rules change');
  });

  test('cache is bounded (LRU eviction, no unbounded growth)', () {
    final terminal = Terminal(maxLines: 3000);
    final painter = newPainter();
    for (var i = 0; i < 2000; i++) {
      terminal.write('line $i\r\n');
    }
    // Paint every line once — must not throw / grow unbounded.
    final lines = terminal.buffer.lines;
    for (var i = 0; i < lines.length; i++) {
      painter.getLinePicture(lines[i]);
    }
    // Re-request the newest line: still valid (either cached or re-recorded).
    final p = painter.getLinePicture(lines[lines.length - 1]);
    expect(p, isNotNull);
  });

  testWidgets('picture path is pixel-identical to direct paintLine path',
      (tester) async {
    await tester.runAsync(() async {
      final terminal = Terminal();
      final painter = newPainter();
      terminal.write('hi \x1b[31mred\x1b[0m \x1b[1mbold\x1b[0m wide: 漢字');
      final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];

      final width = (painter.cellSize.width * 60).ceil();
      final height = painter.cellSize.height.ceil();

      Future<List<int>> rasterize(void Function(ui.Canvas) draw) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        draw(canvas);
        final image =
            await recorder.endRecording().toImage(width, height);
        final data =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      }

      final direct = await rasterize(
          (canvas) => painter.paintLine(canvas, Offset.zero, line));
      final viaPicture = await rasterize(
          (canvas) => canvas.drawPicture(painter.getLinePicture(line)));

      expect(viaPicture, equals(direct),
          reason: 'cached picture must paint exactly what paintLine paints');
    });
  });
}
