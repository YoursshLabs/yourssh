// Terminal.writeBytes must be a drop-in replacement for the app's current
// pipeline — one chunked Utf8Decoder(allowMalformed: true) feeding every
// decoded string to Terminal.write — for any byte stream and any chunking:
// same code points (including U+FFFD for malformed bytes and the dropped
// byte order mark at the start of the stream), same terminal state.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('decodes like Utf8Decoder for hand-picked inputs', () {
    final cases = <List<List<int>>>[
      [
        [0xEF, 0xBB, 0xBF, 0x41],
      ],
      [
        [0xEF, 0xBB],
        [0xBF, 0x41, 0xEF, 0xBB, 0xBF],
      ],
      [
        [0xEF],
        [0xBB, 0x41],
      ],
      [
        [0xE2, 0x82],
        [0xAC, 0x41],
      ],
      [
        [0xE2, 0x82],
        [0x41],
      ],
      [
        [0xF0, 0x9F],
        [0x98],
        [0x80, 0x0A],
      ],
      [
        [0xF0, 0x80, 0x80, 0x41, 0xED, 0xA0, 0x80, 0xC0, 0x80],
      ],
      [
        [0xF4, 0x90, 0x80, 0x80, 0xF8, 0x88, 0x80, 0x80, 0x80, 0x80],
      ],
      [
        [0xC3],
        [0xE2, 0x82, 0xAC],
        [0xE0, 0x80],
        [0x41],
      ],
      [
        [0x1B, 0x5D, 0x30, 0x3B, 0xF0, 0x9F],
        [0x98, 0x80, 0x07, 0x1B],
        [0x5B, 0x31, 0x6D],
      ],
    ];
    for (final chunks in cases) {
      expect(_viaBytes(chunks), _viaStrings(chunks), reason: '$chunks');
      expect(
        _terminalViaBytes(chunks),
        _terminalViaStrings(chunks),
        reason: '$chunks',
      );
    }
  });

  test('decodes like Utf8Decoder for random byte streams and chunkings', () {
    for (var seed = 0; seed < 400; seed++) {
      final r = _Rng(seed);
      final bytes = _randomStream(r);
      final chunks = <List<int>>[];
      var i = 0;
      while (i < bytes.length) {
        final n = r.nextInt(r.chance(30) ? 4 : 300);
        final end = (i + n).clamp(0, bytes.length);
        chunks.add(bytes.sublist(i, end));
        i = end;
      }
      expect(_viaBytes(chunks), _viaStrings(chunks), reason: 'seed $seed');
      if (seed % 4 == 0) {
        expect(
          _terminalViaBytes(chunks),
          _terminalViaStrings(chunks),
          reason: 'seed $seed',
        );
      }
    }
  });
}

class _Rng {
  _Rng(int seed) : _s = (seed * 2654435761 + 0x9E3779B9) & 0xffffffff {
    if (_s == 0) _s = 1;
  }

  int _s;

  int next() {
    var x = _s;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _s = x;
    return x;
  }

  int nextInt(int n) => n <= 0 ? 0 : next() % n;

  bool chance(int percent) => nextInt(100) < percent;
}

List<int> _randomStream(_Rng r) {
  final out = <int>[];
  if (r.chance(20)) out.addAll([0xEF, 0xBB, 0xBF]);
  final pieces = 20 + r.nextInt(200);
  for (var p = 0; p < pieces; p++) {
    switch (r.nextInt(9)) {
      case 0:
      case 1:
        for (var i = r.nextInt(30); i > 0; i--) {
          out.add(0x20 + r.nextInt(95));
        }
      case 2:
        out.addAll(
          utf8.encode(
            String.fromCharCode(
              [0xE9, 0x1EBF, 0x65E5, 0xD55C, 0x2705, 0x0301][r.nextInt(6)],
            ),
          ),
        );
      case 3:
        out.addAll(
          utf8.encode(String.fromCharCode(0x10000 + r.nextInt(0xFFFFF))),
        );
      case 4:
        out.add(0x80 + r.nextInt(0x80)); // stray high byte
      case 5:
        // Truncated or overlong sequence.
        final full = utf8.encode(
          String.fromCharCode(0x800 + r.nextInt(0xF000)),
        );
        out.addAll(full.sublist(0, 1 + r.nextInt(full.length)));
        if (r.chance(50)) {
          out.add([0xC0, 0xC1, 0xE0, 0xED, 0xF0, 0xF4][r.nextInt(6)]);
        }
      case 6:
        out.addAll([0xEF, 0xBB, 0xBF]); // BOM in the middle is kept
      case 7:
        out.addAll(
          utf8.encode(
            ['\x1b[1;31m', '\r\n', '\x1b]0;t\x07', '\x1b['][r.nextInt(4)],
          ),
        );
      default:
        out.add(r.nextInt(256));
    }
  }
  return out;
}

/// Code points and handler calls when fed through Utf8Decoder + write().
List<Object> _viaStrings(List<List<int>> chunks) {
  final log = <Object>[];
  final parser = EscapeParser(_LogHandler(log));
  final sink = const Utf8Decoder(
    allowMalformed: true,
  ).startChunkedConversion(_StringSink(parser.write));
  for (final c in chunks) {
    sink.add(c);
  }
  return log;
}

List<Object> _viaBytes(List<List<int>> chunks) {
  final log = <Object>[];
  final parser = EscapeParser(_LogHandler(log));
  for (final c in chunks) {
    parser.writeBytes(Uint8List.fromList(c));
  }
  return log;
}

List<Object> _terminalViaStrings(List<List<int>> chunks) {
  final t = Terminal(maxLines: 100);
  final sink = const Utf8Decoder(
    allowMalformed: true,
  ).startChunkedConversion(_StringSink(t.write));
  for (final c in chunks) {
    sink.add(c);
  }
  return _state(t);
}

List<Object> _terminalViaBytes(List<List<int>> chunks) {
  final t = Terminal(maxLines: 100);
  for (final c in chunks) {
    t.writeBytes(Uint8List.fromList(c));
  }
  return _state(t);
}

List<Object> _state(Terminal t) {
  final lines = t.buffer.lines;
  return [
    t.buffer.cursorX,
    t.buffer.cursorY,
    t.cursor.foreground,
    t.cursor.attrs,
    for (var i = 0; i < lines.length; i++) ...[
      lines[i].isWrapped,
      ...lines[i].data.sublist(0, lines[i].length * 4),
    ],
  ];
}

class _StringSink implements Sink<String> {
  _StringSink(this.onData);

  final void Function(String) onData;

  @override
  void add(String data) => onData(data);

  @override
  void close() {}
}

class _LogHandler implements EscapeHandler {
  _LogHandler(this.log);

  final List<Object> log;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    log.add(invocation.memberName);
    log.addAll(invocation.positionalArguments.map((a) => '$a'));
    return null;
  }
}
