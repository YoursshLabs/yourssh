// Behavior snapshot for the xterm output path (EscapeParser + Buffer +
// BufferLine). The corpus digests were recorded with the parser/buffer code
// as it was BEFORE the throughput work (fork patch 10), so any optimization
// of Terminal.write must reproduce the exact same terminal state — every
// cell's codepoint/width/fg/bg/attrs, wrap flags, cursor, margins, modes,
// scrollback trimming and callbacks. The fuzz and generic digests were
// re-recorded after the robustness fixes (malformed SGR/erase no longer
// throw, scroll-region lines stay attached, restored cursors are clamped,
// width resizes after the scrollback wrapped keep their order).
//
// Inputs are generated deterministically (own PRNG, no dart:math Random):
//   * four corpora mirroring the throughput benchmark (plain log, SGR-heavy,
//     Vietnamese NFC+NFD / CJK / emoji, full-screen TUI redraws), written in
//     app-sized chunks;
//   * fuzz cases mixing text, controls, ESC/CSI/OSC/SGR sequences, charsets,
//     margins, modes, malformed and oversized sequences, written in random
//     chunk sizes that split escape sequences and surrogate pairs, with
//     occasional resizes, on tiny terminals with tiny scrollback;
//   * the generic EscapeParser path (custom handler) with token offsets.
//
// To re-record after an INTENTIONAL behavior change:
//   flutter test test/widgets/xterm_write_snapshot_test.dart \
//     --dart-define=XTERM_SNAPSHOT_RECORD=true
// and paste the printed values.
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

const _record = bool.fromEnvironment('XTERM_SNAPSHOT_RECORD');

void main() {
  group('corpus snapshots', () {
    for (final entry in _corpusExpectations.entries) {
      test(entry.key, () {
        final spec = _corpusSpecs[entry.key]!;
        final got = spec();
        if (_record) {
          // ignore: avoid_print
          print("RECORD corpus '${entry.key}': 0x${got.toRadixString(16)},");
          return;
        }
        expect(got.toRadixString(16), entry.value.toRadixString(16));
      });
    }
  });

  test('fuzz snapshots', () {
    final got = <int>[for (var i = 0; i < _fuzzCases; i++) _runFuzzCase(i)];
    if (_record) {
      // ignore: avoid_print
      print('fuzz error kinds: ${_Digest.errorCounts}');
      // ignore: avoid_print
      print(
        'RECORD fuzz: [${got.map((d) => '0x${d.toRadixString(16)}').join(', ')}]',
      );
      return;
    }
    final mismatches = <int>[
      for (var i = 0; i < _fuzzCases; i++)
        if (got[i] != _fuzzExpectations[i]) i,
    ];
    expect(mismatches, isEmpty, reason: 'fuzz cases with different state');
  });

  test('generic EscapeParser handler snapshot', () {
    final got = _runGenericParser();
    if (_record) {
      // ignore: avoid_print
      print('RECORD generic: 0x${got.toRadixString(16)}');
      return;
    }
    expect(got.toRadixString(16), _genericExpectation.toRadixString(16));
  });
}

// ---------------------------------------------------------------------------
// Expectations (recorded before the optimization).

const _corpusExpectations = <String, int>{
  'plain': 0x3d0f4f99a0e8344e,
  'color': 0x7ef435ec229b9fa0,
  'unicode': 0x4d6f433a28f284c6,
  'tui': 0x32e679a28e937d8b,
  'unicode-split': 0xfecfce7c4a999b7,
  'plain-small-scrollback': 0x35b8b1afd3e97a3a,
};

const _fuzzCases = 240;

const _fuzzExpectations = <int>[
  0x10d365e934ab734c, 0x5178c120bf674633, 0x1d0ebe689b5a420a,
  0x4e9e81ae1ac6fb8a, 0x4d94e0263306be46, 0x749d415cf37378dc,
  0x571b56d717715b18, 0xb6db49b25d92875, 0x4c9f3d1fb3959157,
  0x1cbf16231bf0a9b, 0x4af43cc586e331c2, 0x5d10fda4f49bacb4,
  0x5a85c2069291520, 0xf1b39b9521beb45, 0x8e30df2168bdb95,
  0x3dc0997b4df8cdac, 0x197efe79f724c513, 0x7d3c73f4ee72f898,
  0x2529a65559871a22, 0x71c67f653e85ec9f, 0x633dee9d7732fd50,
  0x25fa42c8a9a5e526, 0x65e1d41dc1ed8458, 0x118130fbdb6909ba,
  0x3f0996f6f1eeea2a, 0x4084c299513e38b1, 0x47ce6c3f7b44fab5,
  0x5aa666c67a064f11, 0x239842e1dbd85cb5, 0x24716658bc41d540,
  0x37912a0cbb7fbec2, 0x1b3bbed8d32376a1, 0x57c7f4074e3d2688,
  0x4db44504a29a40c2, 0x2ac9816d6ed16579, 0x5fc1a4f50f515b71,
  0x9451dc3eec15341, 0x3ad4cb1dbc7fba0c, 0x755d3aa40ade6b3c,
  0x698d0173513c0147, 0x413a850fa86301ab, 0x768499bcb2bb3fed,
  0x2fed3786fe683e18, 0x65f0439485e32b0, 0x33f8326ab18893df,
  0x23e0d82eb6d770cc, 0x3a5c222543920854, 0x4edcec0f6f8dacb5,
  0xf389a63f77d2235, 0x31ee4ab870c41985, 0x62dd1d3d270c00a6,
  0x76337a55ea9258d4, 0x4367a4e88c75c8e2, 0xb36b05d425f0966,
  0x484a4de2cdc7bf6b, 0x1ad50771c76c1115, 0xdb7472f55e345ab,
  0x22e9ccccaae5e152, 0x78ad16116c2f5bf8, 0x2f9e54c361ae2764,
  0xe4e5cc2501a6230, 0x199bfbb5b40bba44, 0x42b9c2307da6c052,
  0x74560a523335a8e2, 0x3eff991bed92f2d3, 0x561cbcb6b2de119a,
  0x4c8034c132aae3f2, 0x2a8f98ca255fdc27, 0x31678cfff883e1de,
  0x29424eb0592fd617, 0x1b4c54c292bf70b5, 0x1902673499211b3b,
  0x566ff3e1aa44a11, 0x75cc6f0fcc0f9fcb, 0x252fa1272cfecdd0,
  0x1eff1f698b809397, 0x74d7df8f676f82bd, 0xfc2e305f7011a4c,
  0x68740856a5e94141, 0x5d1edbb4198e7850, 0x24c273712a8d3c70,
  0x277f1f5864344769, 0x31fec18f5ab03085, 0x439dca7bc79e63b9,
  0x4501f35c41815d91, 0x3401d5de68f30c76, 0x5daedc4d59bf23ab,
  0x607359ee457e4ff6, 0x75bc264bdb30791f, 0x4302fe5be1155e6d,
  0x6967af2bcb15e984, 0xd162d38563b6ded, 0x2027c46244c9bfad,
  0x6da3b8ab76bb1a84, 0x4736fd455dceaa78, 0x4683aaa6a87b9d22,
  0x47abdf13b0861f4a, 0xab1e103dc2e7379, 0x27e8c3cc58843603,
  0x2f7f31d870a528bd, 0x6f71ec1e7b0c8407, 0x346f7bcdd8bad16e,
  0x7d08553b511a0922, 0x739f5818db1e3fb3, 0x5606ce1ab4b8c4a,
  0x1b6b09e446cd0f50, 0x507b78a76f656ba5, 0x11ebd33ec59399f3,
  0x1dfdaf9b36ae3950, 0x58bf76e1c26110ee, 0x68bf1d9f1046d7cf,
  0xcc14b198c2c9abc, 0x24038a015eccf7b4, 0x6b0458031041107,
  0x4979112c56624bf5, 0xafb4fc693011bba, 0x2da9791ef24882ec,
  0x761a1af51c59c6ac, 0x2af59ee994fcd461, 0xce3dee19bff5b5,
  0x5f5ea0e71bc8c22d, 0xc966f8381002718, 0x2b3bfb6128529abf,
  0x1584eb317524b6fb, 0x51ff0498bd3c2024, 0x2ed8a0e38a69ed0b,
  0x6cdc0e61f00d25bd, 0x7448ec00f9f2c94c, 0x5f3a80473df0bef5,
  0x2b190cc6f6d09ffe, 0x3186da30d367bff9, 0x7a5d3b4710b4e3ed,
  0x653f4007fdf0ec19, 0x6c9cd76bbb5d825c, 0x3577e74706684e2c,
  0x6ff9d256f69af4f1, 0x236b504d21f24f6e, 0x13af4d9a97839e1e,
  0x18093c12c3068d9f, 0x5c670f80370b17ce, 0x2983fc78dd532efe,
  0x1d6f560240d56f1e, 0x3ddee258f7c53ed2, 0xae6934037836160,
  0x117eec41c4f763cb, 0x3db8e15c52b68eb0, 0x68aab0d6eb57d69d,
  0x362fa69cf391331a, 0x4ecee3fbdeace4ab, 0x40bbb27c335e6dc1,
  0x41f48e68f429f20a, 0x2b89650285a2107a, 0x1224e770d1273007,
  0x52bc0e49871b08d3, 0x1d67133950b07600, 0x6a4a36bf7615193c,
  0x106e791b997dafd2, 0x1141eb1c3a13dc8c, 0x381dffba3894488c,
  0x62746e3bbd5c4755, 0x4b036afd5ace551f, 0x5a862ea8fb941c9e,
  0x36a87c932ad38dc2, 0x60995f7208aee8c9, 0x1b4bad1f3f13c6c1,
  0x4355f005489dc45c, 0x67c649b7d21d10b9, 0x616f9ad91deb5bfd,
  0x22e4ee73ce99505c, 0x524abba0451e2e33, 0x5102d09a25c131b1,
  0x1cea862e24392385, 0x6b11e6215b44233e, 0x52506e8d84714ddf,
  0x67510bbcd773568c, 0x701c052c39b4bcd4, 0x6b3501863b5da451,
  0x80ad3282b13b822, 0x5887a3fbb68229f9, 0x427b444f16c67e68,
  0x4fc00a923e8bdf36, 0xa4be2da843e2041, 0x6e4dca33b3b6f1a,
  0x4ae7c5be8d7273c7, 0x7fc9cc69f56571ef, 0x1ebe975b8bcf8b83,
  0x419226930ec5dbba, 0x2f9ed2a2baa5c21d, 0xd673051e43d55a0,
  0x6a6bef5799446b56, 0x7beda403d5692c1f, 0x126e6357e4ffe54,
  0x49d804c1ae799772, 0x3f28c15c6d53d750, 0x3b0c0051a13c727,
  0x518991111f8761b5, 0x75081ca14d7db397, 0x325837e4f0d2993b,
  0x153d10af3f5d89f9, 0x7837b3e81a4acdfb, 0x2635d6231174d513,
  0x25cf42eaad424714, 0x4abe721e66337d36, 0x420b6a78ec3da1c4,
  0x511f06de8b6e5e50, 0x235f4e2eff9538e2, 0x261c4b9421a45410,
  0x3028e342239c569a, 0x5d7c41ee3dcb937c, 0xc81753e556b987d,
  0x53af728bf2ae7f15, 0x5a15c4cddfb89d84, 0x5209bff8b7e193e0,
  0x3d5e6a1ddabb1876, 0x529fd91cc6e5c8c4, 0x210c12c0557cfc6a,
  0x3cf9cc13bab2144b, 0xfd7e69d814125aa, 0x63b24dbd11cc5815,
  0x2c314b9072227d4a, 0x674af4dbc5d3c8a3, 0x2801a7eafcb8c269,
  0x20a789b04ecdfb50, 0x42d0796c573750c6, 0x37d59fbc262f9484,
  0x6552001134e6578f, 0x32c5b9aca72c4757, 0x39dc5fc0581ce0e4,
  0x58716a1094d94fd0, 0x7ac12eb6988c9e2, 0x2f74b8f63f983a2e,
  0x7429707316935ee3, 0x1fdc613f950a23c1, 0x7dd22ce375f8d26c,
  0x756cb87282f5b2e8, 0x4bd3ee62cb10d2a2, 0x2bde2431a34fe914,
  0x7a005821ecebf09e, 0x29cdfe612d10a0fa, 0x23b4af3edbecf4e0,
];

const _genericExpectation = 0x78df8e7902adebc1;

// ---------------------------------------------------------------------------
// Deterministic PRNG (xorshift32) — independent of the SDK's Random.

class _Rng {
  _Rng(int seed) : _s = (seed * 2654435761 + 0x9E3779B9) & 0xffffffff {
    if (_s == 0) _s = 1;
    for (var i = 0; i < 4; i++) {
      next();
    }
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

  int nextInt(int n) => next() % n;

  bool chance(int percent) => nextInt(100) < percent;

  T pick<T>(List<T> items) => items[nextInt(items.length)];
}

// ---------------------------------------------------------------------------
// Digest.

class _Digest {
  int h = 0x3bf29ce484222325;

  void add(int v) {
    h ^= v & 0xffffffff;
    h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    h ^= (v >> 32) & 0xffffffff;
    h = (h * 0x100000001b3) & 0x7fffffffffffffff;
  }

  void addString(String s) {
    add(s.length);
    for (var i = 0; i < s.length; i++) {
      add(s.codeUnitAt(i));
    }
  }

  void addBuffer(Buffer b) {
    add(b.lines.length);
    add(b.lines.droppedLines);
    add(b.cursorX);
    add(b.cursorY);
    add(b.marginTop);
    add(b.marginBottom);
    for (var i = 0; i < b.lines.length; i++) {
      // Defensive: a hole in the circular buffer is recorded, not thrown.
      BufferLine? line;
      try {
        line = b.lines[i];
      } catch (_) {}
      if (line == null) {
        add(0xDEAD);
        continue;
      }
      add(line.attached ? 1 : 0);
      add(line.length);
      add(line.isWrapped ? 1 : 0);
      add(line.getTrimmedLength());
      final data = line.data;
      final n = line.length * 4;
      for (var j = 0; j < n; j++) {
        add(data[j]);
      }
    }
  }

  void addTerminal(Terminal t) {
    add(t.viewWidth);
    add(t.viewHeight);
    addBuffer(t.mainBuffer);
    addBuffer(t.altBuffer);
    add(t.isUsingAltBuffer ? 1 : 0);
    add(t.cursor.foreground);
    add(t.cursor.background);
    add(t.cursor.attrs);
    add(t.insertMode ? 1 : 0);
    add(t.lineFeedMode ? 1 : 0);
    add(t.cursorKeysMode ? 1 : 0);
    add(t.reverseDisplayMode ? 1 : 0);
    add(t.originMode ? 1 : 0);
    add(t.autoWrapMode ? 1 : 0);
    add(t.mouseMode.index);
    add(t.mouseReportMode.index);
    add(t.cursorBlinkMode ? 1 : 0);
    add(t.cursorVisibleMode ? 1 : 0);
    add(t.appKeypadMode ? 1 : 0);
    add(t.reportFocusMode ? 1 : 0);
    add(t.altBufferMouseScrollMode ? 1 : 0);
    add(t.bracketedPasteMode ? 1 : 0);
  }

  static final errorCounts = <int, int>{};

  void addError(Object e) {
    // Classify instead of runtimeType.toString() so the digest does not
    // depend on implementation class names.
    final kind = e is IndexError
        ? 1
        : e is RangeError
        ? 2
        : e is AssertionError
        ? 3
        : e is StateError
        ? 4
        : e is ArgumentError
        ? 5
        : 9;
    errorCounts[kind] = (errorCounts[kind] ?? 0) + 1;
    add(0xE0000 + kind);
  }
}

Terminal _newRecordingTerminal(_Digest d, {int maxLines = 1000}) {
  return Terminal(
    maxLines: maxLines,
    onOutput: (s) {
      d.add(0x0A);
      d.addString(s);
    },
    onBell: () => d.add(0xBE11),
    onTitleChange: (s) {
      d.add(0x7171);
      d.addString(s);
    },
    onIconChange: (s) {
      d.add(0x1C0);
      d.addString(s);
    },
    onPrivateOSC: (code, args) {
      d.add(0x05C);
      d.addString(code);
      d.add(args.length);
      for (final a in args) {
        d.addString(a);
      }
    },
  );
}

void _write(Terminal t, _Digest d, String s) {
  try {
    t.write(s);
  } catch (e) {
    d.addError(e);
    // Probe the state a throwing write leaves behind: REP repeats the last
    // written character, after the unprocessed rest of the chunk.
    try {
      t.write('\x1b[b');
    } catch (e) {
      d.addError(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Corpora (deterministic ports of the benchmark generator, ~1 MB each).

const _words = [
  'connection', 'established', 'request', 'response', 'timeout', 'user', //
  'session', 'server', 'client', 'error', 'warning', 'debug', 'info',
  'deploy', 'build', 'cache', 'index', 'query',
];

const _viNfc = [
  'Xin chào thế giới',
  'Tiếng Việt có dấu',
  'Người dùng đăng nhập',
  'Kết nối thành công',
];

const _viNfd = [
  'Xin chào thế giới',
  'Tiếng Việt có dấu',
  'Người dùng đăng nhập',
  'Kết nối thành công',
];

String _plainCorpus(int bytes) {
  final r = _Rng(1);
  final sb = StringBuffer();
  var i = 0;
  while (sb.length < bytes) {
    final level = r.pick(['INFO', 'WARN', 'DEBUG']);
    final ws = [for (var k = 0; k < 12; k++) r.pick(_words)].join(' ');
    final mm = (i % 60).toString().padLeft(2, '0');
    final ss = ((i * 7) % 60).toString().padLeft(2, '0');
    sb.write('2026-11-12T10:$mm:${ss}Z [$level] $ws id=$i\n');
    i++;
  }
  return sb.toString();
}

String _colorCorpus(int bytes) {
  final r = _Rng(2);
  final sb = StringBuffer();
  var i = 0;
  while (sb.length < bytes) {
    final parts = <String>[];
    for (var k = 0; k < 10; k++) {
      final c = r.pick([31, 32, 33, 34, 35, 36, 90, 91, 92, 93, 94]);
      parts.add('\x1b[${c}m${r.pick(_words)}\x1b[0m');
    }
    sb.write(
      '\x1b[1;37m${i.toString().padLeft(8, '0')}\x1b[0m '
      '${parts.join(' ')}\n',
    );
    i++;
  }
  return sb.toString();
}

String _unicodeCorpus(int bytes) {
  final r = _Rng(3);
  final sb = StringBuffer();
  var i = 0;
  while (sb.length < bytes) {
    final s = i.isOdd ? r.pick(_viNfd) : r.pick(_viNfc);
    sb.write(
      '${i.toString().padLeft(6, '0')} $s '
      '日本語のテキスト '
      '中文字符 한국어 '
      '\u{1F642}\u{1F680}\u{1F468}‍\u{1F469}‍\u{1F467} '
      '✅\n',
    );
    i++;
  }
  return sb.toString();
}

String _tuiCorpus(int frames) {
  final r = _Rng(4);
  final sb = StringBuffer('\x1b[?1049h\x1b[?25l');
  for (var fr = 0; fr < frames; fr++) {
    sb.write('\x1b[H');
    for (var row = 0; row < 40; row++) {
      final bar = '|' * r.nextInt(61);
      final pct = (r.nextInt(10000) / 100).toStringAsFixed(2).padLeft(6);
      sb.write(
        '\x1b[${row + 1};1H\x1b[48;5;${(row * 3 + fr) % 256}m'
        '\x1b[38;5;${(row * 7) % 256}m${row.toString().padLeft(3)} '
        '${bar.padRight(60)}\x1b[0m $pct% ${'proc$row'.padRight(20)}\x1b[K',
      );
    }
  }
  sb.write('\x1b[?25h\x1b[?1049l');
  return sb.toString();
}

int _runCorpus(
  String text,
  int chunk, {
  int maxLines = 10000,
  _Rng? randomChunks,
}) {
  final d = _Digest();
  final t = _newRecordingTerminal(d, maxLines: maxLines);
  t.resize(120, 40);
  var i = 0;
  while (i < text.length) {
    final size = randomChunks == null ? chunk : 1 + randomChunks.nextInt(chunk);
    final end = i + size > text.length ? text.length : i + size;
    _write(t, d, text.substring(i, end));
    i = end;
  }
  d.addTerminal(t);
  return d.h;
}

final _corpusSpecs = <String, int Function()>{
  'plain': () => _runCorpus(_plainCorpus(1 << 20), 16384),
  'color': () => _runCorpus(_colorCorpus(1 << 20), 32768),
  'unicode': () => _runCorpus(_unicodeCorpus(1 << 19), 16384),
  'tui': () => _runCorpus(_tuiCorpus(200), 65536),
  'unicode-split': () =>
      _runCorpus(_unicodeCorpus(1 << 18), 97, randomChunks: _Rng(5)),
  'plain-small-scrollback': () =>
      _runCorpus(_plainCorpus(1 << 19), 4099, maxLines: 300),
};

// ---------------------------------------------------------------------------
// Fuzz.

const _unicodePool = [
  '日本',
  '한',
  '\u{1F642}',
  '\u{1F468}‍\u{1F469}',
  '✅',
  'é',
  'é',
  'ấ',
  'ờ',
  '́',
  '̶',
  '⃝',
  '️',
  '​',
  '­',
  ' ',
  '\u0080',
  '\u009B',
  '\u007F',
  '\u0010',
  '\u001A',
  '\u001F',
  '\uD800',
  '\uDC00',
  '\u{10FFFF}',
  '\u{E0001}',
  '\u{1F1FA}\u{1F1F8}',
  'Ａ',
  '　',
  'ำ',
  '가',
  'क्',
  'x̀̀',
  '中́',
  '─│',
  '\u{20000}',
];

const _escChars = '78DEHMc#P+*()=>[]\\_^XZ01Bxé\u{1F642}\x1b\x07\x00';

const _csiFinals = '@ABCDEFGHJKLMPSTXbcdfghlmnrt';

const _modes = [
  1, 3, 4, 5, 6, 7, 9, 12, 20, 25, 47, 66, 1000, 1001, 1002, 1003, 1004, //
  1005, 1006, 1007, 1015, 1047, 1048, 1049, 2004, 2026, 9999,
];

String _fuzzParam(_Rng r) {
  switch (r.nextInt(8)) {
    case 0:
      return '';
    case 1:
      return '0';
    case 2:
      return '${1 + r.nextInt(5)}';
    case 3:
      return '${r.nextInt(130)}';
    case 4:
      return '${r.nextInt(70000)}';
    case 5:
      return '99999999999999999999';
    default:
      return '${1 + r.nextInt(40)}';
  }
}

String _fuzzSgr(_Rng r) {
  final params = <String>[];
  final n = r.nextInt(6);
  for (var i = 0; i < n; i++) {
    switch (r.nextInt(12)) {
      case 0:
        params.add('38;5;${r.nextInt(256)}');
      case 1:
        params.add('48;5;${r.nextInt(256)}');
      case 2:
        params.add(
          '38;2;${r.nextInt(256)};${r.nextInt(256)};${r.nextInt(256)}',
        );
      case 3:
        params.add(
          '48;2;${r.nextInt(256)};${r.nextInt(256)};${r.nextInt(256)}',
        );
      case 4:
        // Truncated extended colors (the old parser throws on these).
        params.add(r.pick(['38', '48', '38;5', '48;2;1', '38;2;1;2']));
      case 5:
        params.add('${r.pick([0, 1, 2, 3, 4, 5, 7, 8, 9])}');
      case 6:
        params.add('${r.pick([21, 22, 23, 24, 25, 27, 28, 29, 39, 49])}');
      case 7:
        params.add('${30 + r.nextInt(18)}');
      case 8:
        params.add('${90 + r.nextInt(18)}');
      case 9:
        params.add('');
      default:
        params.add('${r.nextInt(120)}');
    }
  }
  return '\x1b[${params.join(';')}m';
}

String _fuzzToken(_Rng r) {
  switch (r.nextInt(22)) {
    case 0:
    case 1:
    case 2:
      final n = 1 + r.nextInt(r.chance(20) ? 300 : 40);
      final sb = StringBuffer();
      for (var i = 0; i < n; i++) {
        sb.writeCharCode(0x20 + r.nextInt(95));
      }
      return sb.toString();
    case 3:
    case 4:
      final sb = StringBuffer();
      final n = 1 + r.nextInt(12);
      for (var i = 0; i < n; i++) {
        sb.write(r.pick(_unicodePool));
      }
      return sb.toString();
    case 5:
      return r.pick(_viNfd) + r.pick(_viNfc);
    case 6:
      return r.pick(['\r\n', '\n', '\r', '\t', '\b', '\x07', '\x0b', '\x0c']);
    case 7:
      return String.fromCharCode(r.nextInt(0x20));
    case 8:
      return '\x1b${_escChars[r.nextInt(_escChars.length)]}';
    case 9:
      return r.pick(['\x1b(0', '\x1b(B', '\x1b)0', '\x1b)B', '\x0e', '\x0f']) +
          (r.chance(50) ? 'lqqkxmjntuvw_`~abc' : '');
    case 10:
    case 11:
    case 12:
      final prefix = r.chance(70) ? '' : r.pick(['?', '>', '=', '<', ':']);
      final n = r.nextInt(4);
      final params = [for (var i = 0; i < n; i++) _fuzzParam(r)];
      final inter = r.chance(90) ? '' : r.pick([' ', '!', '\$', '"', '\x00']);
      final fin = r.chance(90)
          ? _csiFinals[r.nextInt(_csiFinals.length)]
          : String.fromCharCode(0x40 + r.nextInt(0x3f));
      final garbage = r.chance(95) ? '' : r.pick(['\x1b', 'é', ':', '?']);
      return '\x1b[$prefix${params.join(';')}$garbage$inter$fin';
    case 13:
      final on = r.chance(50) ? 'h' : 'l';
      final n = 1 + r.nextInt(3);
      return '\x1b[?${[for (var i = 0; i < n; i++) r.pick(_modes)].join(';')}$on';
    case 14:
    case 15:
      return _fuzzSgr(r);
    case 16:
      final term = r.pick(['\x07', '\x1b\\', '\x1bx', '']);
      final code = r.pick(['0', '1', '2', '7', '133', '8', '', '0;a;b']);
      return '\x1b]$code;${r.pick(['title', 'été \u{1F642}', '', 'a;b;c'])}$term';
    case 17:
      final top = 1 + r.nextInt(30);
      final bottom = top + r.nextInt(30);
      return r.chance(80) ? '\x1b[$top;${bottom}r' : '\x1b[r';
    case 18:
      return '\x1b[${r.nextInt(40)};${r.nextInt(130)}H';
    case 19:
      return 'Z\x1b[${r.nextInt(300)}b';
    case 20:
      if (r.chance(3)) return '\x1b[${'1;' * 2100}m';
      if (r.chance(2)) return '\x1b]0;${'y' * 70000}';
      return '\x1b[${r.nextInt(5)}${r.pick(['J', 'K', '@', 'P', 'X', 'L', 'M', 'S', 'T'])}';
    default:
      return r.pick([
        '\x1b7',
        '\x1b8',
        '\x1bD',
        '\x1bM',
        '\x1bE',
        '\x1b[s',
        '\x1bH',
      ]);
  }
}

const _sizes = [
  [1, 1], [2, 2], [5, 3], [12, 6], [20, 8], [33, 12], [80, 24], [120, 40], //
];

int _runFuzzCase(int seed) {
  final r = _Rng(1000 + seed);
  final d = _Digest();
  final size = _sizes[seed % _sizes.length];
  // The buffers are created at the default 80x24 before the first resize,
  // so scrollback smaller than 24 lines is not a valid configuration.
  final maxLines = (size[1] < 24 ? 24 : size[1]) + r.nextInt(40);
  final t = _newRecordingTerminal(d, maxLines: maxLines);
  t.reflowEnabled = seed % 3 != 0;
  t.resize(size[0], size[1]);

  final sb = StringBuffer();
  final tokens = 200 + r.nextInt(600);
  for (var i = 0; i < tokens; i++) {
    sb.write(_fuzzToken(r));
  }
  final text = sb.toString();

  var i = 0;
  var writes = 0;
  while (i < text.length) {
    final maxChunk = r.pick([1, 3, 17, 256, 4096]);
    final end = (i + 1 + r.nextInt(maxChunk)).clamp(0, text.length);
    _write(t, d, text.substring(i, end));
    i = end;
    writes++;
    if (r.chance(2)) {
      // Heights above maxLines are invalid input for Buffer.resize. Width
      // changes after the scrollback wrapped around are covered too (they
      // scrambled the scrollback before the replaceWith fix).
      final s = r.pick(_sizes);
      if (s[1] <= maxLines) {
        try {
          t.resize(s[0], s[1]);
        } catch (e) {
          d.addError(e);
        }
      }
    }
    if (writes % 16 == 0) d.addTerminal(t);
  }
  d.addTerminal(t);
  return d.h;
}

// ---------------------------------------------------------------------------
// Generic handler path (EscapeParser driven by a non-Terminal handler, as
// the TerminalDebugger does).

class _LoggingHandler implements EscapeHandler {
  _LoggingHandler(this.d);

  final _Digest d;

  late EscapeParser parser;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    d.addString(invocation.memberName.toString());
    d.add(parser.tokenBegin);
    d.add(parser.tokenEnd);
    for (final a in invocation.positionalArguments) {
      if (a is int) {
        d.add(a);
      } else if (a is String) {
        d.addString(a);
      } else if (a is List) {
        d.add(a.length);
        for (final s in a) {
          d.addString('$s');
        }
      } else if (a is Enum) {
        d.add(a.index + 0x1000);
      } else if (a is bool) {
        d.add(a ? 0xB1 : 0xB0);
      } else {
        d.addString('$a');
      }
    }
    return null;
  }
}

int _runGenericParser() {
  final d = _Digest();
  final h = _LoggingHandler(d);
  final p = EscapeParser(h);
  h.parser = p;
  for (var c = 0; c < 40; c++) {
    final r = _Rng(5000 + c);
    final sb = StringBuffer();
    final tokens = 50 + r.nextInt(200);
    for (var i = 0; i < tokens; i++) {
      sb.write(_fuzzToken(r));
    }
    final text = sb.toString();
    var i = 0;
    while (i < text.length) {
      final end = (i + 1 + r.nextInt(r.pick([1, 5, 64, 2048]))).clamp(
        0,
        text.length,
      );
      try {
        p.write(text.substring(i, end));
      } catch (e) {
        d.addError(e);
      }
      i = end;
    }
  }
  return d.h;
}
