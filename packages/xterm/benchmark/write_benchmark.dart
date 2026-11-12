// Terminal.write throughput benchmark (pure Dart, no Flutter).
//
// Feeds corpus files through `Terminal.write` exactly like the app does:
// UTF-8 bytes are decoded chunk by chunk (Utf8Decoder, allowMalformed) and
// every decoded String is written to a 120x40 terminal with 10 000 lines of
// scrollback. Only the write calls are timed.
//
// The xterm package cannot resolve its own dev_dependencies, so compile it
// against the app's package config:
//
//   cd packages/xterm
//   dart compile exe --packages=../../app/.dart_tool/package_config.json \
//     benchmark/write_benchmark.dart -o /tmp/xterm_write_bench
//   /tmp/xterm_write_bench --dir=<corpus dir> [--chunk=65536] [--reps=5] \
//     [--bytes] [plain color unicode tui]
//
// `--bytes` also measures the whole pipeline from raw bytes: chunked
// Utf8Decoder + Terminal.write (what the app does today) and
// Terminal.writeBytes (decoding inside the terminal). Each corpus also
// prints a digest of the final screen + scrollback state so two builds can
// be compared for identical behavior.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xterm/src/core/buffer/buffer.dart';
import 'package:xterm/src/terminal.dart';

void main(List<String> args) {
  var dir = '.';
  var chunk = 65536;
  var reps = 5;
  var maxBytes = 1 << 62;
  var bytesMode = false;
  final corpora = <String>[];
  for (final a in args) {
    if (a.startsWith('--dir=')) {
      dir = a.substring(6);
    } else if (a.startsWith('--chunk=')) {
      chunk = int.parse(a.substring(8));
    } else if (a.startsWith('--reps=')) {
      reps = int.parse(a.substring(7));
    } else if (a.startsWith('--max=')) {
      maxBytes = int.parse(a.substring(6));
    } else if (a == '--bytes') {
      bytesMode = true;
    } else {
      corpora.add(a);
    }
  }
  if (corpora.isEmpty) corpora.addAll(['plain', 'color', 'unicode', 'tui']);

  for (final name in corpora) {
    var bytes = File('$dir/$name.txt').readAsBytesSync();
    if (bytes.length > maxBytes) bytes = bytes.sublist(0, maxBytes);
    final byteChunks = <Uint8List>[
      for (var i = 0; i < bytes.length; i += chunk)
        Uint8List.sublistView(
          bytes,
          i,
          i + chunk > bytes.length ? bytes.length : i + chunk,
        ),
    ];
    final strings = decodeChunks(byteChunks);
    final mb = bytes.length / (1024 * 1024);

    final times = <double>[];
    var digest = 0;
    for (var r = 0; r < reps; r++) {
      final t = newTerminal();
      final sw = Stopwatch()..start();
      for (final s in strings) {
        t.write(s);
      }
      sw.stop();
      times.add(sw.elapsedMicroseconds / 1e6);
      digest = terminalDigest(t);
    }
    report('write', name, mb, times, digest);

    if (bytesMode) {
      final ptimes = <double>[];
      final btimes = <double>[];
      var pdigest = 0;
      var bdigest = 0;
      for (var r = 0; r < reps; r++) {
        final t = newTerminal();
        final sw = Stopwatch()..start();
        final sink = const Utf8Decoder(allowMalformed: true)
            .startChunkedConversion(_WriteSink(t));
        for (final c in byteChunks) {
          sink.add(c);
        }
        sw.stop();
        ptimes.add(sw.elapsedMicroseconds / 1e6);
        pdigest = terminalDigest(t);

        final t2 = newTerminal();
        final sw2 = Stopwatch()..start();
        for (final c in byteChunks) {
          t2.writeBytes(c);
        }
        sw2.stop();
        btimes.add(sw2.elapsedMicroseconds / 1e6);
        bdigest = terminalDigest(t2);
      }
      report('decode+wr', name, mb, ptimes, pdigest);
      report('writeBytes', name, mb, btimes, bdigest);
    }
  }
}

class _WriteSink implements Sink<String> {
  _WriteSink(this.terminal);
  final Terminal terminal;
  @override
  void add(String data) => terminal.write(data);
  @override
  void close() {}
}

Terminal newTerminal() {
  final t = Terminal(maxLines: 10000);
  t.resize(120, 40);
  return t;
}

List<String> decodeChunks(List<Uint8List> chunks) {
  final out = <String>[];
  final sink = const Utf8Decoder(allowMalformed: true)
      .startChunkedConversion(_ListSink(out));
  for (final c in chunks) {
    sink.add(c);
  }
  sink.close();
  return out;
}

class _ListSink implements Sink<String> {
  _ListSink(this.out);
  final List<String> out;
  @override
  void add(String data) {
    if (data.isNotEmpty) out.add(data);
  }

  @override
  void close() {}
}

void report(String api, String name, double mb, List<double> times, int d) {
  final sorted = [...times]..sort();
  final best = sorted.first;
  final median = sorted[sorted.length ~/ 2];
  stdout.writeln(
    '${api.padRight(10)} ${name.padRight(8)} '
    '${mb.toStringAsFixed(1).padLeft(5)} MB  '
    'best ${(mb / best).toStringAsFixed(1).padLeft(6)} MB/s  '
    'median ${(mb / median).toStringAsFixed(1).padLeft(6)} MB/s  '
    'digest ${d.toRadixString(16)}',
  );
}

/// FNV-1a style digest over everything observable in both buffers.
int terminalDigest(Terminal t) {
  var h = 0xcbf29ce484222325;
  void mix(int v) {
    h ^= v & 0xffffffff;
    h = (h * 0x100000001b3) & 0x7fffffffffffffff;
  }

  void mixBuffer(Buffer b) {
    mix(b.lines.length);
    mix(b.cursorX);
    mix(b.cursorY);
    mix(b.marginTop);
    mix(b.marginBottom);
    for (var i = 0; i < b.lines.length; i++) {
      final line = b.lines[i];
      mix(line.length);
      mix(line.isWrapped ? 1 : 0);
      final data = line.data;
      final n = line.length * 4;
      for (var j = 0; j < n; j++) {
        mix(data[j]);
      }
    }
  }

  mixBuffer(t.mainBuffer);
  mixBuffer(t.altBuffer);
  mix(t.isUsingAltBuffer ? 1 : 0);
  mix(t.cursor.foreground);
  mix(t.cursor.background);
  mix(t.cursor.attrs);
  return h;
}
