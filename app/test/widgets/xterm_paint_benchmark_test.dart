// Microbenchmark: per-frame paint cost of a full viewport, direct per-cell
// path vs the cached line-picture path, and flood frames (every line
// re-recorded) with paragraphs vs the glyph atlas. Not a strict perf test (no
// assert on timings) — prints numbers for the changelog/PR.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  floodBenchmark();

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

/// Flood frames: every visible line is new, so each frame re-records all of
/// them. Paragraph-per-cell vs glyph atlas (atlas warmed up first).
void floodBenchmark() {
  testWidgets('paint benchmark: flood frame, paragraphs vs glyph atlas',
      (tester) async {
    const cols = 121;
    const rows = 40;
    const frames = 60;
    final samples = <String, String>{
      'plain': '2026-11-12T10:00:00Z [INFO] connection established request '
          'response timeout user session server client error id=12345',
      'color': '\x1b[1;37m00000042\x1b[0m \x1b[31mresponse\x1b[0m '
          '\x1b[91mbuild\x1b[0m \x1b[94mbuild\x1b[0m \x1b[93mwarning\x1b[0m '
          '\x1b[94mindex\x1b[0m \x1b[93minfo\x1b[0m \x1b[90msession\x1b[0m '
          '\x1b[32mclient\x1b[0m \x1b[36mquery\x1b[0m',
      'tui': '\x1b[48;5;9m\x1b[38;5;21m 12 ${'|' * 44}${' ' * 16}\x1b[0m '
          ' 64.33% proc12              ',
    };
    await tester.runAsync(() async {
      final loader = FontLoader('MesloLGS NF');
      for (final f in ['MesloLGS NF Regular.ttf', 'MesloLGS NF Bold.ttf']) {
        final bytes = File('assets/fonts/nerd/$f').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    });
    for (final sample in samples.entries) {
      final terminal = Terminal(maxLines: 1000)..resize(cols, rows);
      for (var i = 0; i < rows; i++) {
        terminal.write('${sample.value}\r\n');
      }
      final lines = terminal.buffer.lines;
      final first = lines.length - rows;
      Future<double> run(TerminalPainter painter) async {
        for (var i = first; i < lines.length; i++) {
          painter.getLinePicture(lines[i]);
        }
        await tester.runAsync(painter.glyphAtlasIdle);
        final sw = Stopwatch()..start();
        for (var f = 0; f < frames; f++) {
          painter.keywordRules = const []; // drop every cached line picture
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          for (var i = first; i < lines.length; i++) {
            canvas.save();
            canvas.translate(0, (i - first) * painter.cellSize.height);
            canvas.drawPicture(painter.getLinePicture(lines[i]));
            canvas.restore();
          }
          recorder.endRecording().dispose();
        }
        return sw.elapsedMicroseconds / frames / 1000;
      }

      TerminalPainter make(bool atlas) => TerminalPainter(
            theme: TerminalThemes.defaultTheme,
            textStyle: const TerminalStyle(fontFamily: 'MesloLGS NF'),
            textScaler: TextScaler.noScaling,
            devicePixelRatio: 2,
            useGlyphAtlas: atlas,
          );
      final paragraphs = await run(make(false));
      final atlasPainter = make(true);
      final atlas = await run(atlasPainter);
      // ignore: avoid_print
      print('BENCH flood ${sample.key} ${rows}x$cols: paragraphs '
          '${paragraphs.toStringAsFixed(2)} ms/frame, atlas '
          '${atlas.toStringAsFixed(2)} ms/frame '
          '(atlas glyphs ${atlasPainter.debugAtlasGlyphCount}, '
          'fallback ${atlasPainter.debugFallbackGlyphCount})');
    }
  });
}
