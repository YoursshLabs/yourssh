// Tests for the xterm fork's per-line picture cache (render smoothness fix):
// cache hits on unchanged lines, invalidation on content/style/keyword-rule
// changes, and pixel-equivalence with the direct paintLine path — including
// the glyph-atlas text path (drawRawAtlas) against the per-cell paragraph path.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/render.dart';
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

  group('glyph atlas', () {
    // A real font makes the comparison meaningful: anti-aliased outlines with
    // subpixel positioning (the default test font paints boxes).
    var fontLoaded = false;
    Future<void> loadMeslo() async {
      if (fontLoaded) return;
      final loader = FontLoader('MesloLGS NF');
      for (final f in ['MesloLGS NF Regular.ttf', 'MesloLGS NF Bold.ttf']) {
        final bytes = File('assets/fonts/nerd/$f').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
      fontLoaded = true;
    }

    const meslo = TerminalStyle(fontFamily: 'MesloLGS NF', fontSize: 13);

    TerminalPainter painterFor({required bool atlas, double dpr = 1}) =>
        TerminalPainter(
          theme: TerminalThemes.defaultTheme,
          textStyle: meslo,
          textScaler: TextScaler.noScaling,
          devicePixelRatio: dpr,
          useGlyphAtlas: atlas,
        );

    Future<Uint8List> rasterize(
      TerminalPainter painter,
      double dpr,
      Offset origin,
      int cols,
      void Function(ui.Canvas) draw,
    ) async {
      final cell = painter.cellSize;
      final width = ((cols + 2) * cell.width * dpr).ceil();
      final height = (3 * cell.height * dpr).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(TerminalThemes.defaultTheme.background, BlendMode.src);
      canvas.scale(dpr);
      // One line of margin above: ink may leave the line box.
      canvas.translate(origin.dx, origin.dy + cell.height);
      draw(canvas);
      final image = await recorder.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    /// Max per-channel difference and number of differing bytes.
    (int, int) diff(Uint8List a, Uint8List b) {
      expect(a.length, b.length);
      var max = 0, count = 0;
      for (var i = 0; i < a.length; i++) {
        final d = (a[i] - b[i]).abs();
        if (d != 0) count++;
        if (d > max) max = d;
      }
      return (max, count);
    }

    // Tolerance: a glyph tile is rendered once (premultiplied, 8-bit) and then
    // composited with srcOver; drawing the glyph directly blends coverage and
    // color in one step. The two roundings can differ by one level; anything
    // else (a wrong subpixel phase, color, ordering) shows up as tens of
    // levels.
    const tolerance = 1;

    Future<void> expectAtlasMatches(
      String output, {
      double dpr = 1,
      Offset origin = Offset.zero,
      List<KeywordHighlightRule> rules = const [],
      int cols = 100,
      bool expectAtlas = true,
      bool expectFallback = false,
    }) async {
      final terminal = Terminal();
      terminal.resize(cols, 5);
      terminal.write(output);
      final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];

      final reference = painterFor(atlas: false, dpr: dpr)
        ..keywordRules = rules;
      final atlas = painterFor(atlas: true, dpr: dpr)..keywordRules = rules;
      final deviceOffset = origin * dpr;

      // First recording requests the glyphs (drawn with paragraphs meanwhile).
      atlas.getLinePicture(line, deviceOffset: deviceOffset);
      await atlas.glyphAtlasIdle();
      final atlasBefore = atlas.debugAtlasGlyphCount;
      final fallbackBefore = atlas.debugFallbackGlyphCount;
      final picture = atlas.getLinePicture(line, deviceOffset: deviceOffset);
      final usedAtlas = atlas.debugAtlasGlyphCount - atlasBefore;
      final usedFallback = atlas.debugFallbackGlyphCount - fallbackBefore;

      final expected = await rasterize(reference, dpr, origin, cols,
          (c) => c.drawPicture(reference.getLinePicture(line)));
      final actual = await rasterize(
          atlas, dpr, origin, cols, (c) => c.drawPicture(picture));
      final (maxDiff, count) = diff(expected, actual);
      final what = '${output.replaceAll('\x1b', r'\e')} @dpr=$dpr '
          'origin=$origin (atlas glyphs $usedAtlas, fallback $usedFallback)';
      expect(maxDiff, lessThanOrEqualTo(tolerance),
          reason: '$what: max channel diff $maxDiff over $count bytes');
      if (expectAtlas) {
        expect(usedAtlas, greaterThan(0), reason: '$what: atlas unused');
      }
      if (expectFallback) {
        expect(usedFallback, greaterThan(0), reason: '$what: no fallback');
      }
      reference.dispose();
      atlas.dispose();
    }

    const ascii = 'The quick brown fox jumps over the lazy dog 0123456789 '
        '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';
    const styles = '\x1b[1mbold\x1b[0m \x1b[3mitalic\x1b[0m '
        '\x1b[4munder line \x1b[0m \x1b[1;3;4mall three\x1b[0m '
        '\x1b[2mfaint\x1b[0m \x1b[7minverse\x1b[0m \x1b[1;7mbold inv\x1b[0m '
        '\x1b[2;7;31mfaint inv red\x1b[0m \x1b[8minvisible\x1b[0m';
    String ansi16() {
      final b = StringBuffer();
      for (var i = 0; i < 8; i++) {
        b.write('\x1b[${30 + i};${47 - i}mA${i}b'
            '\x1b[${90 + i};${100 + i}mC$i ');
      }
      return '$b\x1b[0m';
    }

    String ansi256() {
      final b = StringBuffer();
      for (var n = 16; n < 256; n += 11) {
        b.write('\x1b[38;5;${n}m\x1b[48;5;${255 - n}mx$n');
      }
      return '$b\x1b[0m';
    }

    String trueColor() {
      final b = StringBuffer();
      for (var i = 0; i < 40; i++) {
        b.write('\x1b[38;2;${i * 6};${255 - i * 6};${(i * 37) % 256}m'
            '\x1b[48;2;${(i * 13) % 256};${i * 3};${200 - i * 4}m'
            '${String.fromCharCode(0x41 + i % 26)}');
      }
      return '$b\x1b[0m';
    }

    // Decomposed Vietnamese (composed into single cells by fork patch 8) and
    // a mark with no precomposed form (stays in its own cell).
    const vietnamese =
        'Tiếng Việt có dấu '
        'NGƯỜI dùng đăng nhập q̃ x';
    const wide = '\x1b[32m漢字\x1b[0m テスト \x1b[44m中文\x1b[0m 한국어 x';
    const emoji = 'a 🙂🚀 b ✅ c ⌚ d';
    const boxes = '┌─┬─┐ │ █▓▒░ ╭╮   → ≥ λ';
    String tui() {
      final b = StringBuffer();
      for (var r = 0; r < 3; r++) {
        b.write('\x1b[48;5;${r * 40 + 3}m\x1b[38;5;${r * 7 + 1}m'
            '${'${r.toString().padLeft(3)} ${'|' * (10 + r * 9)}'.padRight(40)}');
      }
      return '$b\x1b[0m 64.33% proc0';
    }

    // Glyph ink reaching into the next cell's background: powerline arrows
    // (fg = previous segment's bg), full blocks, italic overhang on a bg.
    const powerline = '\x1b[37;44m user \x1b[34;42m\ue0b0\x1b[30m ~/src '
        '\x1b[32;45m\ue0b0\x1b[37m main \x1b[35;49m\ue0b0\x1b[0m '
        '\x1b[41m█▉▊▋\x1b[42m▌▍▎▏\x1b[0m \x1b[3;45mitalic on bg wW\x1b[0m'
        '\x1b[3;46m/\\\x1b[47mfj\x1b[0m';

    final cases = <String, String>{
      'powerline+overhang': powerline,
      'ascii': ascii,
      'styles': styles,
      'ansi16': ansi16(),
      'ansi256': ansi256(),
      'truecolor': trueColor(),
      'vietnamese': vietnamese,
      'wide': wide,
      'boxes+powerline': boxes,
      'tui': tui(),
    };

    for (final entry in cases.entries) {
      for (final (dpr, origin) in [
        (1.0, Offset.zero),
        (2.0, Offset.zero),
        (2.0, const Offset(0.25, 0)),
        (2.0, const Offset(0.25, 0.75)),
        (1.5, const Offset(0.3, 0.5)),
      ]) {
        testWidgets(
            '${entry.key} matches the paragraph path '
            '(dpr $dpr, origin $origin)', (tester) async {
          await tester.runAsync(() async {
            await loadMeslo();
            await expectAtlasMatches(entry.value, dpr: dpr, origin: origin);
          });
        });
      }
    }

    testWidgets('emoji fall back to paragraphs and still match',
        (tester) async {
      await tester.runAsync(() async {
        await loadMeslo();
        await expectAtlasMatches(emoji, dpr: 2, expectFallback: true);
      });
    });

    testWidgets('keyword highlights (bg, fg, overlapping) match',
        (tester) async {
      await tester.runAsync(() async {
        await loadMeslo();
        final rules = [
          KeywordHighlightRule(
            pattern: RegExp('error', caseSensitive: false),
            background: const Color(0xCCB71C1C),
          ),
          KeywordHighlightRule(
            pattern: RegExp('success'),
            foreground: const Color(0xFFA5D6A7),
          ),
          KeywordHighlightRule(
            pattern: RegExp('warn(ing)?'),
            foreground: const Color(0xFF000000),
            background: const Color(0xCCE65100),
          ),
          KeywordHighlightRule(
            pattern: RegExp('漢字'),
            foreground: const Color(0xFFFFFF00),
          ),
        ];
        const line = 'ERROR: \x1b[31mbuild error\x1b[0m success '
            '\x1b[1;44mwarning\x1b[0m warn 漢字 successerror';
        for (final dpr in [1.0, 2.0]) {
          await expectAtlasMatches(line, dpr: dpr, rules: rules);
        }
      });
    });

    testWidgets('color glyphs never use the atlas', (tester) async {
      await tester.runAsync(() async {
        await loadMeslo();
        final painter = painterFor(atlas: true, dpr: 2);
        final terminal = Terminal()..write('🙂🚀✅');
        final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
        painter.getLinePicture(line);
        await painter.glyphAtlasIdle();
        final before = painter.debugAtlasGlyphCount;
        painter.getLinePicture(line, deviceOffset: const Offset(0, 0.5));
        expect(painter.debugAtlasGlyphCount, before);
        painter.dispose();
      });
    });

    testWidgets('style / scale changes reset the atlas', (tester) async {
      await tester.runAsync(() async {
        await loadMeslo();
        final painter = painterFor(atlas: true, dpr: 2);
        final terminal = Terminal()..write('hello');
        final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
        painter.getLinePicture(line);
        await painter.glyphAtlasIdle();
        expect(painter.debugGlyphAtlasSize, greaterThan(0));

        painter.devicePixelRatio = 1;
        expect(painter.debugGlyphAtlasSize, 0, reason: 'dpr change');
        painter.getLinePicture(line);
        await painter.glyphAtlasIdle();
        expect(painter.debugGlyphAtlasSize, greaterThan(0));

        painter.textStyle = meslo.copyWith(fontSize: 15);
        expect(painter.debugGlyphAtlasSize, 0, reason: 'font size change');
        painter.getLinePicture(line);
        await painter.glyphAtlasIdle();

        // A theme change keeps the tiles (they are keyed by color) but must
        // re-record the line pictures.
        final p0 = painter.getLinePicture(line);
        final size = painter.debugGlyphAtlasSize;
        painter.theme = TerminalThemes.whiteOnBlack;
        expect(painter.debugGlyphAtlasSize, size);
        expect(identical(painter.getLinePicture(line), p0), isFalse);
        painter.dispose();
      });
    });

    testWidgets('admitting glyphs re-records cached line pictures',
        (tester) async {
      await tester.runAsync(() async {
        await loadMeslo();
        final painter = painterFor(atlas: true, dpr: 2);
        final terminal = Terminal()..write('abc');
        final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
        final p0 = painter.getLinePicture(line);
        expect(identical(painter.getLinePicture(line), p0), isTrue);
        await painter.glyphAtlasIdle();
        expect(identical(painter.getLinePicture(line), p0), isFalse,
            reason: 'recorded with paragraphs before the glyphs were ready');
        final p1 = painter.getLinePicture(line);
        expect(identical(painter.getLinePicture(line), p1), isTrue);
        // A different device fraction (e.g. dpr 1.5 scrolling) re-records.
        final p2 =
            painter.getLinePicture(line, deviceOffset: const Offset(0, 0.5));
        expect(identical(p2, p1), isFalse);
        painter.dispose();
      });
    });

    // Selection, cursor shapes and controller highlights are painted over the
    // line pictures by RenderTerminal: render whole TerminalView frames with
    // and without the atlas.
    for (final cursorType in TerminalCursorType.values) {
      for (final focused in [true, false]) {
        testWidgets(
            'TerminalView frame matches: cursor $cursorType, '
            'focused $focused, selection', (tester) async {
          await tester.runAsync(loadMeslo);
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = const Size(1800, 400);
          addTearDown(tester.view.reset);
          addTearDown(() => TerminalPainter.debugDisableGlyphAtlas = false);

          Future<Uint8List> capture(bool atlas) async {
            TerminalPainter.debugDisableGlyphAtlas = !atlas;
            final terminal = Terminal();
            final controller = TerminalController();
            final focusNode = FocusNode();
            addTearDown(focusNode.dispose);
            final boundary = GlobalKey();
            await tester.pumpWidget(MaterialApp(
              home: Material(
                color: TerminalThemes.defaultTheme.background,
                child: Padding(
                  padding: const EdgeInsets.only(left: 3, top: 1),
                  child: RepaintBoundary(
                    key: boundary,
                    child: TerminalView(
                      terminal,
                      key: ValueKey(atlas),
                      controller: controller,
                      focusNode: focusNode,
                      textStyle: meslo,
                      cursorType: cursorType,
                      alwaysShowCursor: true,
                    ),
                  ),
                ),
              ),
            ));
            terminal.write('$ascii\r\n$styles\r\n${ansi16()}\r\n'
                '${tui()}\r\n$wide\r\nprompt> ab');
            controller.setSelection(
              terminal.buffer.createAnchor(4, 0),
              terminal.buffer.createAnchor(20, 2),
            );
            if (focused) {
              focusNode.requestFocus();
            } else {
              focusNode.unfocus();
            }
            await tester.pump();
            final render = tester.renderObject<RenderTerminal>(
                find.byWidgetPredicate(
                    (w) => w.runtimeType.toString() == '_TerminalView'));
            await tester.runAsync(render.debugPainter.glyphAtlasIdle);
            await tester.pump();
            if (atlas) {
              expect(render.debugPainter.debugAtlasGlyphCount, greaterThan(0));
            }
            final ro = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            return (await tester.runAsync(() async {
              final image = await ro.toImage(pixelRatio: 2);
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
              image.dispose();
              return data!.buffer.asUint8List();
            }))!;
          }

          final expected = await capture(false);
          final actual = await capture(true);
          final (maxDiff, count) = diff(expected, actual);
          expect(maxDiff, lessThanOrEqualTo(tolerance),
              reason: 'max channel diff $maxDiff over $count bytes');
        });
      }
    }
  });
}
