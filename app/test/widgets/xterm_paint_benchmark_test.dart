// Microbenchmark: per-frame paint cost of a full viewport, direct per-cell
// path vs the cached line-picture path. Not a strict perf test (no assert on
// timings) — prints numbers for the changelog/PR.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paint benchmark: direct vs picture cache', () {
    const cols = 180;
    const rows = 50;
    const frames = 120;

    final terminal = Terminal(maxLines: 1000);
    terminal.resize(cols, rows);
    for (var i = 0; i < rows; i++) {
      terminal.write(
          'job-$i \x1b[32mOK\x1b[0m ${'x' * (cols - 20)}\r\n');
    }
    final lines = terminal.buffer.lines;

    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
    );

    // Warm the paragraph cache for both paths.
    for (var i = 0; i < lines.length; i++) {
      painter.paintLine(ui.Canvas(ui.PictureRecorder()), Offset.zero, lines[i]);
    }

    final sw1 = Stopwatch()..start();
    for (var f = 0; f < frames; f++) {
      final canvas = ui.Canvas(ui.PictureRecorder());
      for (var i = 0; i < lines.length; i++) {
        painter.paintLine(
            canvas, Offset(0, i * painter.cellSize.height), lines[i]);
      }
    }
    sw1.stop();

    final sw2 = Stopwatch()..start();
    for (var f = 0; f < frames; f++) {
      final canvas = ui.Canvas(ui.PictureRecorder());
      for (var i = 0; i < lines.length; i++) {
        canvas.save();
        canvas.translate(0, i * painter.cellSize.height);
        canvas.drawPicture(painter.getLinePicture(lines[i]));
        canvas.restore();
      }
    }
    sw2.stop();

    final perFrameDirect = sw1.elapsedMicroseconds / frames / 1000;
    final perFrameCached = sw2.elapsedMicroseconds / frames / 1000;
    // ignore: avoid_print
    print('BENCH ${rows}x$cols, $frames frames:');
    // ignore: avoid_print
    print('  direct per-cell  : ${perFrameDirect.toStringAsFixed(2)} ms/frame');
    // ignore: avoid_print
    print('  line-picture LRU : ${perFrameCached.toStringAsFixed(2)} ms/frame');
  });
}
