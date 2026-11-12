// Glyph atlas vs paragraph path, pixel for pixel, on the real engine backend
// (the unit test in test/widgets/xterm_line_picture_cache_test.dart runs on
// flutter_tester's software Skia). Manual run, not CI:
//
//   cd app && flutter test integration_test/terminal_atlas_pixel_test.dart -d macos
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Bundled with the app (pubspec fonts), so no FontLoader needed.
  const style = TerminalStyle(fontFamily: 'MesloLGS NF', fontSize: 13);

  const ascii = 'The quick brown fox jumps over the lazy dog 0123456789 '
      '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
  const styles = '\x1b[1mbold\x1b[0m \x1b[3mitalic\x1b[0m '
      '\x1b[2mfaint\x1b[0m \x1b[7minverse\x1b[0m \x1b[1;7mbold inv\x1b[0m '
      '\x1b[2;7;31mfaint inv red\x1b[0m \x1b[4munder line\x1b[0m';
  final lines = <String, String>{
    'ascii': ascii,
    'styles': styles,
    'ansi16': [
      for (var i = 0; i < 8; i++)
        '\x1b[${30 + i};${47 - i}mA${i}b\x1b[${90 + i};${100 + i}mC$i ',
    ].join(),
    'ansi256': [
      for (var n = 16; n < 256; n += 11)
        '\x1b[38;5;${n}m\x1b[48;5;${255 - n}mx$n',
    ].join(),
    'truecolor': [
      for (var i = 0; i < 40; i++)
        '\x1b[38;2;${i * 6};${255 - i * 6};${(i * 37) % 256}m'
            '\x1b[48;2;${(i * 13) % 256};${i * 3};${200 - i * 4}m'
            '${String.fromCharCode(0x41 + i % 26)}',
    ].join(),
    'vietnamese': 'Tiếng Việt có dấu '
        'NGƯỜI dùng đăng nhập',
    'wide+emoji': '\x1b[32m漢字\x1b[0m テスト \x1b[44m中文\x1b[0m 한국어 🙂🚀 ✅ x',
    'powerline': '\x1b[37;44m user \x1b[34;42m\x1b[30m ~/src '
        '\x1b[32;45m\x1b[37m main \x1b[35;49m\x1b[0m '
        '\x1b[41m█▉▊▋\x1b[42m▌▍▎▏\x1b[0m ┌─┬─┐ \x1b[3;45mitalic on bg wW\x1b[0m',
    'tui': '\x1b[48;5;43m\x1b[38;5;8m 1 ${'|' * 30}${' ' * 20}\x1b[0m '
        '64.33% proc1',
  };

  Future<Uint8List> rasterize(
    TerminalPainter painter,
    double dpr,
    Offset origin,
    ui.Picture picture,
  ) async {
    final cell = painter.cellSize;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(TerminalThemes.defaultTheme.background, BlendMode.src);
    canvas.scale(dpr);
    canvas.translate(origin.dx, origin.dy + cell.height);
    canvas.drawPicture(picture);
    final image = await recorder.endRecording().toImage(
        (102 * cell.width * dpr).ceil(), (3 * cell.height * dpr).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  testWidgets('atlas path matches the paragraph path on this backend',
      (tester) async {
    // ignore: avoid_print
    print('backend: ${ui.ImageFilter.isShaderFilterSupported ? 'Impeller' : 'Skia'}');
    final failures = <String>[];
    await tester.runAsync(() async {
      for (final (dpr, origin) in [
        (2.0, Offset.zero),
        (2.0, const Offset(0.25, 0)),
        (2.0, const Offset(0.25, 0.75)),
        (1.0, Offset.zero),
        (1.5, const Offset(0.3, 0.5)),
      ]) {
        for (final entry in lines.entries) {
          final terminal = Terminal()..resize(100, 3);
          terminal.write(entry.value);
          final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
          TerminalPainter make(bool atlas) => TerminalPainter(
                theme: TerminalThemes.defaultTheme,
                textStyle: style,
                textScaler: TextScaler.noScaling,
                devicePixelRatio: dpr,
                useGlyphAtlas: atlas,
              );
          final reference = make(false);
          final atlas = make(true);
          final deviceOffset = origin * dpr;
          atlas.getLinePicture(line, deviceOffset: deviceOffset);
          await atlas.glyphAtlasIdle();
          final picture = atlas.getLinePicture(line, deviceOffset: deviceOffset);
          final a = await rasterize(
              reference, dpr, origin, reference.getLinePicture(line));
          final b = await rasterize(atlas, dpr, origin, picture);
          var max = 0, count = 0;
          for (var i = 0; i < a.length; i++) {
            final d = (a[i] - b[i]).abs();
            if (d > 0) count++;
            if (d > max) max = d;
          }
          final report = '${entry.key} dpr=$dpr origin=$origin: max diff '
              '$max over $count bytes, atlas glyphs ${atlas.debugAtlasGlyphCount}'
              ', fallback ${atlas.debugFallbackGlyphCount}';
          // ignore: avoid_print
          print(report);
          if (max > 1) failures.add(report);
          reference.dispose();
          atlas.dispose();
        }
      }
    });
    expect(failures, isEmpty);
  });
}
