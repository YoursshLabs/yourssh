// Measurement-only micro-benchmarks (JIT; relative numbers).
//   flutter test test/perf_micro_bench_test.dart --dart-define=BENCH_DIR=...
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

const _bench = String.fromEnvironment('BENCH_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('(a) Terminal.write parse throughput', skip: _bench.isEmpty ? 'set --dart-define=BENCH_DIR' : false, () {
    for (final c in ['plain', 'color', 'unicode', 'tui']) {
      final bytes = File('$_bench/$c.txt').readAsBytesSync();
      // First 8 MB max to keep JIT run short; decode like the app (utf8, 64KB chunks)
      final n = bytes.length < 8 * 1024 * 1024 ? bytes.length : 8 * 1024 * 1024;
      final text = const Utf8Decoder(allowMalformed: true).convert(bytes.sublist(0, n));
      final t = Terminal(maxLines: 10000);
      t.resize(120, 40);
      const chunk = 16384;
      final sw = Stopwatch()..start();
      for (var i = 0; i < text.length; i += chunk) {
        t.write(text.substring(i, i + chunk > text.length ? text.length : i + chunk));
      }
      sw.stop();
      final mb = n / 1048576;
      // ignore: avoid_print
      print('PARSE $c ${mb.toStringAsFixed(1)}MB ${sw.elapsedMilliseconds}ms ${(mb / (sw.elapsedMicroseconds / 1e6)).toStringAsFixed(1)} MB/s');
    }
  });

  test('(b) paint cost per frame', skip: _bench.isEmpty ? 'set --dart-define=BENCH_DIR' : false, () {
    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
    );
    final t = Terminal(maxLines: 10000);
    t.resize(120, 40);
    String row(int seed) =>
        List.generate(120, (i) => String.fromCharCode(33 + (i * 7 + seed) % 90)).join();
    for (var i = 0; i < 200; i++) {
      t.write('\x1b[3${i % 8}m${row(i)}\x1b[0m\r\n');
    }
    final h = t.viewHeight;
    List<BufferLine> visible() {
      final lines = t.buffer.lines;
      return [for (var i = lines.length - h; i < lines.length; i++) lines[i]];
    }

    double bench(String name, int frames, void Function(int f) mutate) {
      // warm
      for (var w = 0; w < 20; w++) {
        mutate(w);
        _paintFrame(painter, visible());
      }
      final sw = Stopwatch();
      final mw = Stopwatch();
      for (var f = 0; f < frames; f++) {
        mw.start();
        mutate(f);
        mw.stop();
        sw.start();
        _paintFrame(painter, visible());
        sw.stop();
      }
      final per = sw.elapsedMicroseconds / frames / 1000;
      // ignore: avoid_print
      print('  (parse/mutate only: ${(mw.elapsedMicroseconds / frames / 1000).toStringAsFixed(3)} ms/frame)');
      // ignore: avoid_print
      print('PAINT $name ${per.toStringAsFixed(3)} ms/frame');
      return per;
    }

    bench('steady', 300, (_) {});
    bench('full-screen change each frame', 300, (f) {
      t.write('\x1b[H');
      for (var r = 0; r < h; r++) {
        t.write('${row(f * 13 + r)}${r < h - 1 ? '\r\n' : ''}');
      }
    });
    bench('scroll 1 line/frame', 300, (f) {
      t.write('${row(f)}\r\n');
    });
    // uncached direct path for comparison
    final lines = visible();
    final sw = Stopwatch()..start();
    for (var f = 0; f < 100; f++) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      for (var i = 0; i < lines.length; i++) {
        painter.paintLine(c, Offset(0, i * painter.cellSize.height), lines[i]);
      }
      rec.endRecording().dispose();
    }
    // ignore: avoid_print
    print('PAINT uncached-direct (steady) ${(sw.elapsedMicroseconds / 100 / 1000).toStringAsFixed(3)} ms/frame');
  });
}

void _paintFrame(TerminalPainter painter, List<BufferLine> lines) {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  final ch = painter.cellSize.height;
  for (var i = 0; i < lines.length; i++) {
    final p = painter.getLinePicture(lines[i]);
    canvas.save();
    canvas.translate(0, (i * ch).truncateToDouble());
    canvas.drawPicture(p);
    canvas.restore();
  }
  rec.endRecording().dispose();
}
