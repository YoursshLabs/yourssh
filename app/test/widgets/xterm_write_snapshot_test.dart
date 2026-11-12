// Behavior snapshot for the xterm output path (EscapeParser + Buffer +
// BufferLine). Every digest below was recorded with the parser/buffer code
// as it was BEFORE the throughput work (fork patch 10), so any optimization
// of Terminal.write must reproduce the exact same terminal state — every
// cell's codepoint/width/fg/bg/attrs, wrap flags, cursor, margins, modes,
// scrollback trimming, callbacks, and even the exceptions the old code threw
// on malformed input.
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
  0x38faf5cfdefaaba0, 0x760efb8d93dcc829, 0x28405cfcdacef1f0,
  0x6fb40c2fcd8506c8, 0x3389a4ed1155d184, 0x68657b8b531282bb,
  0x721e0b93320f272f, 0x3bbb94e22bf6271, 0x2a204bb3553cf217,
  0x15b66ee925ac28cf, 0x2a66d99a5fccca4c, 0x463adea89ecbafcd,
  0x6dfde6ef1b5f8690, 0x5753e218a383f861, 0x7499e40311df3ca9,
  0x27e3c0c0ee7b414d, 0x3526145af8e32f9b, 0x6f3cc78e0aaf5653,
  0x4bd2380d0230070b, 0x2161880ab3cf017, 0xaa51ce825b9d9c7, 0x7fbe58901578bf1f,
  0x40b497ad0f6aea49, 0x3a8b45844a1222c, 0x4a50d1b6015ec13a,
  0x181f7d29cea5f6fe, 0x7295eb9cfac1fa90, 0x92aabd9ee418946,
  0x1b538812d044b986, 0x2967cb705cd5c855, 0x18978e534fa906c8,
  0xa36571a22b6a192, 0xf7f1d3933c8d2c7, 0x3d7f067af5125331, 0x109baa932e3fed88,
  0x3def6b1bf56b1481, 0x64b6f4fce5439d6f, 0x6bc53bd6918cbe05,
  0x6856969835f89acc, 0x12a88b57507c7f0c, 0x68e16dee9840f48b,
  0x4ec9ad9945a9fbb, 0x579762bae630d1d3, 0x7d81007c8e7c95dc,
  0x69c510ae409d3af5, 0x3936af7e7d499971, 0x448798d89f0b8f25,
  0x213cbe1d08061b3e, 0xd1856aa99ee4cae, 0x77eb070c6c9fce4c,
  0x537b882ff9c2072e, 0x7869e247c58a672, 0x603d74987a98bc63,
  0x435e7adc6c3f20a3, 0x7c0f0a8fba8ed1e2, 0x476ef0ab1c7a1ee0,
  0x46264dffc6f4deb0, 0x37e6fc5dcdfa3c48, 0x1eb8ace7a22bf478,
  0x57c2b80e367f3a17, 0x5e0acfcd364257b5, 0x635fea8e5b99fd7, 0x371eef555933964,
  0x4c237d4761fd2107, 0x18a099de95b09da0, 0x7038c82e40140101,
  0x691ccf49dce338cc, 0x112e2c12ed76660, 0x319c856b71be8dfa,
  0x44efe57686deb55f, 0xa349cd869f7ab22, 0x54f1e34049b9d650,
  0x5987c1a6d418cc5b, 0x49f80c5e20cfd3aa, 0x5e227ae983a58dc6,
  0x1fa680a44e79d315, 0x7b731e0bb693ee6a, 0x2e2f3fee1340b8ea,
  0x67b938ba14f0fa61, 0x7480007da57f3c20, 0x7050b0d25813e752,
  0x611a1736eae672e1, 0x182b969adf0f71db, 0x6fe7154d529ae278,
  0x1885e852ed4a40cb, 0x6ed48747a5b6730a, 0x4f99b0b0854c5b31,
  0x505999ce0cdaa8d5, 0x16fa9732e9aaf717, 0x62a0c71fa36e966c,
  0x2f4be639edef9890, 0x36f0369ab8bd9024, 0x236cd426fe6a82c, 0xa730d453f831f66,
  0x7ae8c6148768165f, 0x62c2d0f35b0a5c35, 0x63c80f83bf04c5f3,
  0x62b0b0578a25dd36, 0x785df5a8dd2d6c16, 0x6428377edd7c8cdf,
  0x5246ab9c3a750e6, 0x1ca828a16baa3c3b, 0x6e3a9b1c16bcd6b2,
  0x6e4f81032ba893f7, 0x68536c4bffd8b398, 0x437c6503930eeafd,
  0x159544499dcdd197, 0x234af4ef13c0f783, 0x14b5e75a78d4e9f8,
  0x4337c884e55fe4e5, 0x296f8e2503156158, 0x8238728844c86ee,
  0x5216b01b5f2a9001, 0x7d39727daedfcb5, 0x12c4ae00efff1a3e,
  0x34e4b0bdd7fc6231, 0x74891e9cf03a926e, 0x7e9e85e429e4ca7c,
  0xce0581f79e685c7, 0x129ac952365979c4, 0x4b331afbab6b4264, 0xeddee841a4e85ce,
  0x5dbc894d2d3c4042, 0x6648e39175d80717, 0x2c9142f224e2ebe1,
  0x5f59ed65f4b116fa, 0x69b4da178c49d60d, 0x44f86aa246bbf606,
  0x40439664334fba39, 0x34b6b47d729d9aaa, 0x4a9d91750b30652f,
  0x75b13dde2f1aa87e, 0x2bd6f6b7a2b1f0bf, 0x360862b01d56425e,
  0x53f976130cf667fb, 0x44c89759e127561f, 0x75c643b0a7ea3f39,
  0x7409052a0046d046, 0x1e5260e4b93b6d06, 0x772254de29204dc0,
  0x719bee4378eacd6c, 0xd413a6a58cf9dc6, 0x5ee5edc41ca58ec2,
  0x5458cb82305c2ce3, 0x7409569ba7661523, 0x27845c4ad6469aa6,
  0x78a5e6461cf8cff4, 0x76f439de732ed30e, 0x5772eb2d36508b99,
  0xb9e864fad5550dd, 0x310a4c2332158a13, 0x6c83af87d0f7044b,
  0x1224e770d1273007, 0x548ca5dc2bfba52c, 0x5217f73e84c8980b,
  0x79292ac4404a0cfd, 0x929e84aca98cdf0, 0x65f77f8ea4d979ae,
  0x6bfbec295c0f5aeb, 0x1cadeef7b1f7e235, 0x3b00979851fad456,
  0x785169e15aa35a76, 0x3f2001936322d7f0, 0x5243df08758d3375,
  0x17252f7622e65bcb, 0x328e887705499700, 0x7fa162a52cf8f324,
  0x5b1ce045076ab073, 0x741b5003c840644a, 0x2db6ad994565c657,
  0x3d7285ad47231801, 0x21283a06f062ba2d, 0x76724b1a9c5f1b74,
  0x2133481dd92d0f71, 0xd5612f8b8ffd929, 0x50f6abdfa032522, 0x413408c204fa3f95,
  0x76807c424492aed0, 0x60618c9ff1f69922, 0x7abe27713678a787,
  0x286424c333a624e9, 0x6d6184dc42e1ccec, 0x344e886c15e74ee4,
  0x4fd2d2299f77826c, 0xa74143c47b57fd8, 0x34cee42e804f0b90,
  0x2396871458527a08, 0x10f135c6c9a90de9, 0x166124ca9c77a02,
  0x36e5acfd21d51a73, 0x15b9f1316628c1d6, 0x15d15be0b61cc758,
  0x22378ad34007c1d3, 0x1c6a2ebace1cc053, 0x1ddbe94c06202dcc,
  0x1221b79195f24f47, 0x21982fcd5783d6fe, 0x3e47cd5f303ecb31,
  0x4bc07668aa449862, 0x558b5d2444514d1f, 0x4417b377c47498eb,
  0x7e346a0d386d6ce, 0x575f6a4e81a11988, 0x3b0d4c897df7c94d,
  0x795df1280750e505, 0x28aa706455d42cfa, 0x2311956432849a46,
  0x1936f4989503eb0a, 0x47d6255e33caeeed, 0x77cc77d21699812d,
  0x4291534884b3fb92, 0x5b67d9569591d840, 0x1c47abbb7d420111,
  0x2b489e270c194aea, 0x78e67fa0435d8262, 0x4763904fca959bd5,
  0x3e9fa892bb38a00c, 0x2f557878daef08ce, 0x4fdc7f9cb2167a03,
  0x55770460bac98aba, 0x20502b6f9c45b8b2, 0x691edb47f3046bdb,
  0x130dbf81abbdf48, 0x3b77962696f0abf0, 0x25068051b12c59d4,
  0x3360bb67c2cfa3f3, 0x32c9d59e3b01d5d0, 0x4ce0a6d94305cfde,
  0x1021b3fe54908124, 0x5a500761ab560ad9, 0x29ec34055f4f70ce,
  0x381f19ffcd65c422, 0x3b83ecfb66296101, 0x458c9ecab989b01b,
  0x7408fab15528c7f9, 0x7899f78ec2cac41e, 0x684d8bec8b67b0bb,
  0xf7f0dde76afe484, 0x7eff00b1db085fa3, 0x248027d7ba6549e8,
];

const _genericExpectation = 0x2fc6b4e2857b5df5;

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
      // Pre-existing bookkeeping bugs in scroll/insert can leave holes in
      // the circular buffer; those are part of the recorded behavior.
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
      // Heights above maxLines are invalid input for Buffer.resize. With
      // reflow on, only the height changes: a width change after the
      // scrollback wrapped around hits a pre-existing reflow bug
      // (IndexAwareCircularBuffer.replaceWith ignores _startIndex) that
      // scrambles the scrollback, which is not what this test is about.
      final s = r.pick(_sizes);
      if (s[1] <= maxLines) {
        try {
          t.resize(t.reflowEnabled ? t.viewWidth : s[0], s[1]);
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
