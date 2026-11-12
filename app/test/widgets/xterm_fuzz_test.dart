// Fuzz: random escape/byte soup through Terminal.write and writeBytes, with
// scroll regions and resizes interleaved. Nothing may throw out of write and
// the buffers must stay structurally consistent.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

const _seqCount = 50000;
const _maxLines = 60;

/// One random chunk of terminal input, as raw bytes.
List<int> _chunk(Random r) {
  int n(int max) => r.nextInt(max);
  String params() {
    final count = n(6);
    return List.generate(count, (_) {
      switch (n(6)) {
        case 0:
          return '';
        case 1:
          return '${n(300)}';
        case 2:
          return '${n(70000)}';
        case 3:
          return '${n(3)}:${n(10)}';
        case 4:
          return '${[38, 48, 2, 5][n(4)]}';
        default:
          return '${n(10)}';
      }
    }).join(r.nextBool() ? ';' : ':');
  }

  final out = <int>[];
  final parts = 1 + n(4);
  for (var p = 0; p < parts; p++) {
    switch (n(12)) {
      case 0:
      case 1:
      case 2: // CSI with random params / intermediates / final
        final prefix = ['', '?', '>', '<', '=', '!', ' '][n(7)];
        final inter = n(4) == 0 ? String.fromCharCode(0x20 + n(16)) : '';
        final fin = String.fromCharCode(0x40 + n(63));
        out.addAll('\x1b[$prefix${params()}$inter$fin'.codeUnits);
        break;
      case 3: // well-formed scroll region / cursor / erase / scroll
        final fin = ['r', 'H', 'K', 'J', 'L', 'M', 'S', 'T', 'P', '@', 'X', 'A', 'B', 'C', 'D', 'G', 'd', 'm', 'b', 'I', 'Z'][n(21)];
        out.addAll('\x1b[${1 + n(30)};${1 + n(30)}$fin'.codeUnits);
        out.addAll('\x1b[${n(4)}$fin'.codeUnits);
        break;
      case 4: // SGR colour soup, often truncated
        out.addAll('\x1b[${[38, 48][n(2)]};${[2, 5, 7][n(3)]};${n(300)}${n(2) == 0 ? ';${n(300)}' : ''}m'.codeUnits);
        break;
      case 5: // OSC
        out.addAll('\x1b]${n(200)};${'x' * n(20)}${['\x07', '\x1b\\', '', '\x9c'][n(4)]}'.codeUnits);
        break;
      case 6: // DCS / SOS / PM / APC
        out.addAll('${['\x1bP', '\x1bX', '\x1b^', '\x1b_'][n(4)]}${'q' * n(5)}${['\x1b\\', '', '\x07'][n(3)]}'.codeUnits);
        break;
      case 7: // bare ESC + byte
        out.addAll([0x1b, n(256)]);
        break;
      case 8: // C0 / C1 controls
        out.add(n(2) == 0 ? n(0x20) : 0x80 + n(0x20));
        break;
      case 9: // UTF-8 text incl. wide / combining
        out.addAll(utf8.encode(
            ['abc', 'héllo', '日本語', '́', 'é', '😀', '‍', 'ア'][n(8)]));
        break;
      case 10: // truncated UTF-8 / garbage bytes
        out.addAll([0xe6, 0x97, 0xf0, 0x9f, 0x98, 0xff, 0xc0, 0x80][n(8)] == 0
            ? [0xe6]
            : [0xf0, 0x9f, n(256)]);
        break;
      default: // plain text and newlines
        out.addAll(List.generate(1 + n(12), (_) => n(5) == 0 ? 0x0a : 0x20 + n(95)));
    }
  }
  return out;
}

void _checkBuffer(Terminal t, Buffer b, String where) {
  final h = b.height;
  expect(h, greaterThanOrEqualTo(t.viewHeight), reason: where);
  expect(h, lessThanOrEqualTo(_maxLines), reason: where);
  expect(b.scrollBack, h - t.viewHeight, reason: where);
  expect(b.cursorX, inInclusiveRange(0, t.viewWidth), reason: where);
  expect(b.cursorY, inInclusiveRange(0, t.viewHeight - 1), reason: where);
  for (var i = 0; i < h; i++) {
    final line = b.lines[i];
    expect(line.length, t.viewWidth, reason: '$where line $i width');
    expect(line.index, i, reason: '$where line $i index');
  }
}

void _run({
  required int width,
  required int height,
  required bool bytes,
  required int seed,
}) {
  final r = Random(seed);
  final t = Terminal(maxLines: _maxLines);
  t.resize(width, height);
  for (var i = 0; i < _seqCount; i++) {
    if (i % 997 == 0) {
      // resize interleaved, including width changes after scrollback filled
      final big = width > 10;
      t.resize(big ? 20 + r.nextInt(80) : 1 + r.nextInt(5),
          big ? 5 + r.nextInt(25) : 1 + r.nextInt(4));
    }
    if (i % 211 == 0) {
      // scroll region with a random (often non-zero) top margin
      final top = 1 + r.nextInt(t.viewHeight);
      final bottom = top + r.nextInt(t.viewHeight);
      t.write('\x1b[$top;${bottom}r');
    }
    final c = _chunk(r);
    try {
      if (bytes) {
        t.writeBytes(Uint8List.fromList(c));
      } else {
        t.write(utf8.decode(c, allowMalformed: true));
      }
    } catch (e, st) {
      fail('seq #$i ${c.map((b) => b.toRadixString(16)).join(' ')} threw $e\n$st');
    }
    if (i % 500 == 0) {
      _checkBuffer(t, t.buffer, 'seq #$i');
    }
  }
  _checkBuffer(t, t.mainBuffer, 'main end');
  _checkBuffer(t, t.altBuffer, 'alt end');
}

void main() {
  for (final bytes in [false, true]) {
    for (final size in [(80, 24), (2, 1)]) {
      test('fuzz ${bytes ? 'writeBytes' : 'write'} ${size.$1}x${size.$2}', () {
        _run(width: size.$1, height: size.$2, bytes: bytes, seed: 1234 + size.$1);
      }, timeout: const Timeout(Duration(minutes: 5)));
    }
  }
}
