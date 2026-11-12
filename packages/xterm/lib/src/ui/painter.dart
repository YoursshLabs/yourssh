import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:quiver/collection.dart';

import 'package:xterm/src/ui/glyph_atlas.dart';
import 'package:xterm/src/ui/keyword_highlight.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// A recorded picture of one buffer line (text + keyword highlights), painted
/// at origin, valid for a specific [BufferLine.version], glyph-atlas
/// generation (-1: recorded without the atlas) and device-pixel fraction of
/// the place it is drawn at (atlas sprites are aligned to device pixels).
class _LinePicture {
  _LinePicture(this.picture, this.version, this.generation, this.fraction);

  final Picture picture;
  final int version;
  final int generation;
  final int fraction;
}

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    double devicePixelRatio = 1.0,
    bool useGlyphAtlas = true,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler,
        _devicePixelRatio = devicePixelRatio,
        _useGlyphAtlas = useGlyphAtlas;

  /// Disables the glyph atlas in every painter (tests compare both paths).
  @visibleForTesting
  static bool debugDisableGlyphAtlas = false;

  final bool _useGlyphAtlas;

  bool get _atlasEnabled => _useGlyphAtlas && !debugDisableGlyphAtlas;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// [_colorPalette] / theme colors as ARGB ints (atlas keys, no allocation).
  late var _paletteArgb = _buildPaletteArgb();
  late var _themeForegroundArgb = _theme.foreground.toARGB32();
  late var _themeBackgroundArgb = _theme.background.toARGB32();

  Uint32List _buildPaletteArgb() {
    final result = Uint32List(_colorPalette.length);
    for (var i = 0; i < result.length; i++) {
      result[i] = _colorPalette[i].toARGB32();
    }
    return result;
  }

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  /// Recorded pictures of recently painted lines, keyed by line identity and
  /// re-recorded only when the line's [BufferLine.version] changes. Turns the
  /// steady-state per-frame paint cost from O(visible cells) paragraph draws
  /// into O(visible lines) picture replays — the difference between janky and
  /// smooth scrolling/streaming. Insertion-ordered for LRU eviction.
  final _linePictures = <BufferLine, _LinePicture>{};

  /// Upper bound on cached line pictures (~20 viewports of 50 lines); beyond
  /// this the least recently used entries are disposed.
  static const _linePictureCacheLimit = 1024;

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _keywordParagraphs.clear();
    _resetGlyphAtlas();
    _invalidateLinePictures();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _keywordParagraphs.clear();
    _resetGlyphAtlas();
    _invalidateLinePictures();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paletteArgb = _buildPaletteArgb();
    _themeForegroundArgb = value.foreground.toARGB32();
    _themeBackgroundArgb = value.background.toARGB32();
    _paragraphCache.clear();
    _keywordParagraphs.clear();
    // Atlas tiles are keyed by their final color: they stay valid.
    _invalidateLinePictures();
  }

  /// Physical pixels per logical pixel of the surface the pictures end up on.
  /// Atlas tiles are rasterized at this resolution.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _resetGlyphAtlas();
    _invalidateLinePictures();
  }

  /// Called when the glyph atlas admitted new glyphs (cached line pictures
  /// were dropped; repainting lets the visible lines use the new tiles).
  VoidCallback? onGlyphAtlasChanged;

  /// Releases the cached pictures and the atlas page.
  void dispose() {
    _invalidateLinePictures();
    _glyphAtlas?.dispose();
    _glyphAtlas = null;
  }

  /// Keyword highlighting rules baked into the cached line pictures. The
  /// caller (RenderTerminal) only assigns on structural change, so a new
  /// value always invalidates the cache.
  List<KeywordHighlightRule> get keywordRules => _keywordRules;
  List<KeywordHighlightRule> _keywordRules = const [];
  set keywordRules(List<KeywordHighlightRule> value) {
    _keywordRules = value;
    _invalidateLinePictures();
  }

  void _invalidateLinePictures() {
    for (final entry in _linePictures.values) {
      entry.picture.dispose();
    }
    _linePictures.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(
      textStyle.getTextStyle(textScaler: _textScaler),
    );
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _keywordParagraphs.clear();
    _resetGlyphAtlas();
    _invalidateLinePictures();
  }

  /// Returns a picture that paints [line] (text and keyword highlights) at
  /// origin. Cached: the line is re-recorded only when its content version
  /// changed since the last paint.
  ///
  /// [deviceOffset] is where (in physical pixels) the picture's origin will
  /// land; only its fractional part matters. With it, text goes through the
  /// glyph atlas, whose sprites are placed on exact device pixels. Pass null
  /// when the mapping to device pixels is unknown (non-translation transform):
  /// the line is then drawn with paragraphs only.
  Picture getLinePicture(
    BufferLine line, {
    Offset? deviceOffset = Offset.zero,
  }) {
    final atlas = deviceOffset != null && _atlasEnabled;
    var fractionX = 0.0, fractionY = 0.0, fraction = 0;
    if (atlas) {
      fractionX = deviceOffset.dx - deviceOffset.dx.floorToDouble();
      fractionY = deviceOffset.dy - deviceOffset.dy.floorToDouble();
      fraction = (fractionX * 1024).round() << 11 | (fractionY * 1024).round();
    }
    final generation = atlas ? _atlas.generation : -1;

    // Remove + reinsert keeps the map insertion-ordered by recency (LRU).
    final cached = _linePictures.remove(line);
    if (cached != null &&
        cached.version == line.version &&
        cached.generation == generation &&
        cached.fraction == fraction) {
      _linePictures[line] = cached;
      return cached.picture;
    }
    cached?.picture.dispose();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (atlas) {
      _paintLineWithAtlas(canvas, line, fractionX, fractionY);
      _paintLineKeywords(canvas, line);
    } else {
      paintLine(canvas, Offset.zero, line);
      _paintLineKeywords(canvas, line);
    }
    final picture = recorder.endRecording();

    _linePictures[line] = _LinePicture(
      picture,
      line.version,
      generation,
      fraction,
    );
    if (_linePictures.length > _linePictureCacheLimit) {
      final eldest = _linePictures.keys.first;
      _linePictures.remove(eldest)!.picture.dispose();
    }
    return picture;
  }

  // Returns a list mapping string-character index → cell column.
  // getText() emits one code-unit per code-point, skipping continuation cells
  // of double-width characters, so string index ≠ cell column when wide chars
  // are present.
  List<int> _buildStrToCell(BufferLine line) {
    final result = <int>[];
    for (var col = 0; col < line.length; col++) {
      final cp = line.getCodePoint(col);
      if (cp != 0) {
        result.add(col);
        if (line.getWidth(col) == 2) col++;
      }
    }
    return result;
  }

  /// Paints keyword highlights for [line] in line-local coordinates (y = 0).
  /// Recorded into the line's cached picture, so the regex matching runs only
  /// when the line content changes — not on every frame.
  ///
  /// Keyword foregrounds always use paragraphs: they re-draw a glyph over the
  /// cell's own glyph, and two stacked atlas composites can round two levels
  /// away from the paragraph path.
  void _paintLineKeywords(Canvas canvas, BufferLine line) {
    if (_keywordRules.isEmpty) return;

    final lineText = line.getText();
    final strToCell = _buildStrToCell(line);

    for (final rule in _keywordRules) {
      for (final m in rule.pattern.allMatches(lineText)) {
        if (m.start == m.end) continue;

        final startCell =
            m.start < strToCell.length ? strToCell[m.start] : m.start;
        final lastCharCell = m.end > 0 && m.end - 1 < strToCell.length
            ? strToCell[m.end - 1]
            : m.end - 1;
        final endCell =
            lastCharCell + (line.getWidth(lastCharCell) == 2 ? 2 : 1);
        final cellCount = endCell - startCell;

        if (rule.background != null) {
          paintHighlight(
            canvas,
            Offset(startCell * _cellSize.width, 0),
            cellCount,
            rule.background!,
          );
        }

        if (rule.foreground != null) {
          paintKeywordForeground(
            canvas,
            Offset.zero,
            line,
            startCell,
            endCell,
            rule.foreground!,
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Glyph atlas text path.
  //
  // A line recorded through the atlas draws merged background runs with
  // drawRect and its glyphs with one drawRawAtlas per segment, instead of one
  // drawRect + drawParagraph per cell. Output matches paintLine: tiles are the
  // very paragraphs paintLine draws, rendered at the same subpixel phase and
  // vertical fraction and copied onto exact device pixels; cells the atlas
  // cannot represent are drawn by paintCell in place. Batching reorders
  // "bg, glyph, bg, glyph" into "bgs, glyphs" only where that is invisible: a
  // background is never queued under the ink of a queued glyph (the batch is
  // flushed first), using each tile's measured ink bounds.

  GlyphAtlas? _glyphAtlas;

  GlyphAtlas get _atlas => _glyphAtlas ??= GlyphAtlas(
        buildParagraph: _buildGlyphParagraph,
        onChanged: _onGlyphAtlasChanged,
      )..configure(_devicePixelRatio, _cellSize);

  void _resetGlyphAtlas() {
    _glyphAtlas?.configure(_devicePixelRatio, _cellSize);
    _yFractions.clear();
    _yFractionKeys.clear();
    _columnCount = 0;
  }

  void _onGlyphAtlasChanged() {
    _invalidateLinePictures();
    onGlyphAtlasChanged?.call();
  }

  /// Completes once the glyph atlas has no pending glyph requests.
  @visibleForTesting
  Future<void> glyphAtlasIdle() => _glyphAtlas?.whenIdle() ?? Future.value();

  /// Number of glyphs in the atlas.
  @visibleForTesting
  int get debugGlyphAtlasSize => _glyphAtlas?.length ?? 0;

  /// Cells drawn from the atlas / with paragraphs by atlas recordings.
  @visibleForTesting
  int debugAtlasGlyphCount = 0;
  @visibleForTesting
  int debugFallbackGlyphCount = 0;

  // Atlas key: code point | style | phase | y-fraction index | ARGB color.
  static const _kBold = 1 << 21;
  static const _kItalic = 1 << 22;
  static const _kFaint = 1 << 24;
  static const _kPhaseShift = 25;
  static const _kYShift = 27;
  static const _kColorShift = 30;

  Paragraph _buildGlyphParagraph(GlyphSpec spec) {
    // Same paragraph as paintCellForeground / paintKeywordForeground (never
    // underlined: those cells are not drawn from the atlas).
    final style = _textStyle.toTextStyle(
      color: spec.color,
      bold: spec.style & _kBold != 0,
      italic: spec.style & _kItalic != 0,
    );
    final builder = ParagraphBuilder(style.getParagraphStyle())
      ..pushStyle(style.getTextStyle(textScaler: _textScaler))
      ..addText(String.fromCharCode(spec.codePoint));
    return builder.build()
      ..layout(const ParagraphConstraints(width: double.infinity));
  }

  /// Whether a cell may be drawn from the atlas at all (the atlas still
  /// rejects color glyphs and oversized ink when it renders them). Excludes
  /// emoji-heavy blocks, combining and invisible characters; double-width
  /// cells only for CJK / Hangul / fullwidth forms.
  static bool _atlasEligible(int c, int width) {
    if (width == 1) {
      if (c < 0x7F) return c >= 0x20;
      if (c < 0xA0) return false;
      if (c < 0x300) return true; // Latin-1, Latin Extended-A/B, IPA
      if (c < 0x370) return false; // combining diacritical marks
      if (c < 0x530) return c < 0x483 || c > 0x489; // Greek, Cyrillic
      if (c < 0x1E00) return false;
      if (c < 0x2000) return true; // Latin Extended Additional, Greek Ext.
      if (c < 0x2010) return false; // spaces, zero-width, direction marks
      if (c < 0x2028) return true;
      if (c < 0x2030) return false; // separators, embedding controls
      if (c < 0x205F) return true;
      if (c < 0x2070) return false; // invisible operators
      if (c < 0x20D0) return true; // super/subscripts, currency
      if (c < 0x2100) return false; // combining marks for symbols
      if (c < 0x2600) return true; // letterlike … box drawing, shapes
      if (c < 0x27C0) return false; // misc symbols, dingbats (emoji)
      if (c < 0x2C00) return true; // math, arrows, braille
      return c >= 0xE000 && c < 0xF900; // private use (powerline, nerd)
    }
    if (width == 2) {
      return (c >= 0x1100 && c < 0x1160) ||
          (c >= 0x2E80 && c < 0xA4D0) ||
          (c >= 0xAC00 && c < 0xD7A4) ||
          (c >= 0xF900 && c < 0xFB00) ||
          (c >= 0xFF00 && c < 0xFF61) ||
          (c >= 0xFFE0 && c < 0xFFE7);
    }
    return false;
  }

  @pragma('vm:prefer-inline')
  int _foregroundArgb(int cellColor) {
    switch (cellColor & CellColor.typeMask) {
      case CellColor.normal:
        return _themeForegroundArgb;
      case CellColor.named:
      case CellColor.palette:
        return _paletteArgb[cellColor & CellColor.valueMask];
      default:
        return (cellColor & CellColor.valueMask) | 0xFF000000;
    }
  }

  @pragma('vm:prefer-inline')
  int _backgroundArgb(int cellColor) {
    switch (cellColor & CellColor.typeMask) {
      case CellColor.normal:
        return _themeBackgroundArgb;
      case CellColor.named:
      case CellColor.palette:
        return _paletteArgb[cellColor & CellColor.valueMask];
      default:
        return (cellColor & CellColor.valueMask) | 0xFF000000;
    }
  }

  // Device y fractions in use (one at integer scales, a few at fractional
  // ones): tiles are rendered at the fraction they will be drawn at.
  static const _maxYFractions = 8;
  final _yFractions = <double>[];
  final _yFractionKeys = <int>[];

  int _yFractionIndex(double fraction) {
    final key = (fraction * 1024).round();
    final index = _yFractionKeys.indexOf(key);
    if (index >= 0) return index;
    if (_yFractionKeys.length >= _maxYFractions) return -1;
    _yFractionKeys.add(key);
    _yFractions.add(fraction);
    return _yFractionKeys.length - 1;
  }

  // Per-column device geometry for the current scale, cell width and x
  // fraction, relative to the integer device pixel of the line origin.
  var _columnCount = 0;
  var _columnFraction = 0.0;
  var _columnScale = 0.0;
  var _columnWidth = 0.0;

  /// floor(x + 1/8): the device pixel a glyph origin at the cell snaps to.
  var _columnSnap = Int32List(0);

  /// Subpixel phase (quarter pixels) of the glyph origin; -1 when too close
  /// to a phase boundary to be sure which one the rasterizer picks.
  var _columnPhase = Int8List(0);

  /// Device pixel holding the left edge of the cell's background rect.
  var _columnLeft = Int32List(0);

  void _ensureColumns(int count, double fractionX) {
    final scale = _devicePixelRatio;
    final cellWidth = _cellSize.width;
    if (count <= _columnCount &&
        fractionX == _columnFraction &&
        scale == _columnScale &&
        cellWidth == _columnWidth) {
      return;
    }
    _columnFraction = fractionX;
    _columnScale = scale;
    _columnWidth = cellWidth;
    _columnCount = count;
    _columnSnap = Int32List(count);
    _columnPhase = Int8List(count);
    _columnLeft = Int32List(count);
    for (var i = 0; i < count; i++) {
      // The engine maps the cell's x (i * cellWidth) to device space.
      final x = fractionX + scale * (i * cellWidth);
      final v = x + 0.125;
      final snap = v.floor();
      final f = (v - snap) * 4;
      final phase = f.floor();
      final d = f - phase;
      _columnSnap[i] = snap;
      _columnPhase[i] = d < 4e-3 || d > 1 - 4e-3 ? -1 : phase;
      _columnLeft[i] = x.floor();
    }
  }

  // Pending sprites of the current segment.
  static const _noInk = -0x40000000;
  var _spriteTransforms = Float32List(0);
  var _spriteRects = Float32List(0);
  var _spriteCount = 0;

  /// Max exclusive right edge (device px) of the queued sprites' ink.
  var _spriteInkRight = _noInk;

  final _atlasPaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  @pragma('vm:prefer-inline')
  void _addSprite(AtlasGlyph glyph, double tx, double ty, double scale) {
    final i = _spriteCount * 4;
    if (i + 4 > _spriteTransforms.length) {
      final capacity = math.max(512, _spriteTransforms.length * 2);
      _spriteTransforms = Float32List(capacity)..setAll(0, _spriteTransforms);
      _spriteRects = Float32List(capacity)..setAll(0, _spriteRects);
    }
    _spriteTransforms[i] = scale;
    _spriteTransforms[i + 1] = 0;
    _spriteTransforms[i + 2] = tx;
    _spriteTransforms[i + 3] = ty;
    _spriteRects[i] = glyph.left;
    _spriteRects[i + 1] = glyph.top;
    _spriteRects[i + 2] = glyph.right;
    _spriteRects[i + 3] = glyph.bottom;
    _spriteCount++;
  }

  void _flushSprites(Canvas canvas) {
    if (_spriteCount == 0) return;
    final n = _spriteCount * 4;
    canvas.drawRawAtlas(
      _atlas.page!,
      Float32List.sublistView(_spriteTransforms, 0, n),
      Float32List.sublistView(_spriteRects, 0, n),
      null,
      null,
      null,
      _atlasPaint,
    );
    _spriteCount = 0;
    _spriteInkRight = _noInk;
  }

  // The open background run: consecutive cells with the same color.
  var _runOpen = false;
  var _runStart = 0;
  var _runEnd = 0;
  var _runLastCell = 0;
  var _runLastWidth = 1;
  var _runColor = 0;

  void _closeRun(Canvas canvas) {
    if (!_runOpen) return;
    _runOpen = false;
    final cellWidth = _cellSize.width;
    // The union of paintCellBackground's rects (each one pixel wider than its
    // cell); exactly its rect for a single cell.
    canvas.drawRect(
      Rect.fromLTRB(
        _runStart * cellWidth,
        0,
        _runLastCell * cellWidth + (cellWidth * _runLastWidth + 1),
        _cellSize.height,
      ),
      Paint()..color = Color(_runColor),
    );
  }

  /// Draws everything queued, backgrounds first.
  void _flushSegment(Canvas canvas) {
    _closeRun(canvas);
    _flushSprites(canvas);
  }

  final _scratchCell = CellData.empty();

  void _paintLineWithAtlas(
    Canvas canvas,
    BufferLine line,
    double fractionX,
    double fractionY,
  ) {
    final atlas = _atlas;
    final length = line.length;
    _ensureColumns(length, fractionX);
    final yIndex = _yFractionIndex(fractionY);
    final yFraction = yIndex < 0 ? 0.0 : _yFractions[yIndex];
    final data = line.data;
    final cellWidth = _cellSize.width;
    final scale = 1 / _devicePixelRatio;
    // paintLine draws one background rect per cell, each a pixel wider than
    // the cell; where they overlap, an anti-aliased top or bottom row is
    // blended twice. A merged run is only identical when those rows are whole
    // device pixels.
    final rowHeight = _cellSize.height * _devicePixelRatio;
    final mergeRuns =
        fractionY == 0 && rowHeight == rowHeight.roundToDouble();

    _runOpen = false;
    _spriteCount = 0;
    _spriteInkRight = _noInk;

    for (var i = 0; i < length; i++) {
      final o = i * 4;
      final foreground = data[o];
      final background = data[o + 1];
      final attrs = data[o + 2];
      final content = data[o + 3];
      final codePoint = content & CellContent.codepointMask;
      final width = content >> CellContent.widthShift;
      final inverse = attrs & CellFlags.inverse != 0;

      AtlasGlyph? glyph;
      var fallback = false;
      // Same skip rule as paintCellForeground: plain spaces have no ink.
      if (codePoint != 0 &&
          (codePoint != 0x20 || attrs & CellFlags.underline != 0)) {
        final phase = _columnPhase[i];
        // Underlines are rects at the exact fractional x, not snapped to a
        // glyph phase like the outlines: a tile cannot reproduce their ends.
        if (yIndex < 0 ||
            phase < 0 ||
            attrs & CellFlags.underline != 0 ||
            !_atlasEligible(codePoint, width)) {
          fallback = true;
        } else {
          final colorArgb = inverse
              ? _backgroundArgb(background)
              : _foregroundArgb(foreground);
          final style = (attrs & CellFlags.bold != 0 ? _kBold : 0) |
              (attrs & CellFlags.italic != 0 ? _kItalic : 0) |
              (attrs & CellFlags.faint != 0 ? _kFaint : 0);
          final key = codePoint |
              style |
              phase << _kPhaseShift |
              yIndex << _kYShift |
              colorArgb << _kColorShift;
          glyph = atlas.lookup(key);
          if (glyph == null) {
            fallback = true;
            if (atlas.shouldRequest(key)) {
              var color = inverse
                  ? resolveBackgroundColor(background)
                  : resolveForegroundColor(foreground);
              if (attrs & CellFlags.faint != 0) {
                color = color.withOpacity(0.5);
              }
              atlas.request(GlyphSpec(
                key: key,
                codePoint: codePoint,
                style: style,
                color: color,
                phase: phase,
                yFraction: yFraction,
              ));
            }
          }
        }
      }

      if (fallback) {
        // Keep the exact paint order around a cell drawn the old way.
        _flushSegment(canvas);
        line.getCellData(i, _scratchCell);
        paintCell(canvas, Offset(i * cellWidth, 0), _scratchCell);
        debugFallbackGlyphCount++;
        if (width == 2) i++;
        continue;
      }

      // Background, resolved like paintCellBackground.
      if (inverse || background & CellColor.typeMask != CellColor.normal) {
        final color = inverse
            ? _foregroundArgb(foreground)
            : _backgroundArgb(background);
        // paintLine draws this rect after the glyphs of earlier cells: if
        // their ink reaches it, they must be drawn first.
        if (_spriteInkRight > _columnLeft[i]) _flushSegment(canvas);
        final cells = width == 2 ? 2 : 1;
        if (mergeRuns && _runOpen && _runColor == color && _runEnd == i) {
          _runLastCell = i;
          _runLastWidth = cells;
          _runEnd = i + cells;
        } else {
          _closeRun(canvas);
          _runOpen = true;
          _runStart = i;
          _runLastCell = i;
          _runLastWidth = cells;
          _runEnd = i + cells;
          _runColor = color;
        }
      } else {
        _closeRun(canvas);
      }

      if (glyph != null) {
        debugAtlasGlyphCount++;
        if (!glyph.isEmpty) {
          final snap = _columnSnap[i];
          _addSprite(
            glyph,
            (snap + glyph.dx - fractionX) * scale,
            (glyph.dy - fractionY) * scale,
            scale,
          );
          final inkRight = snap + glyph.inkRight;
          if (inkRight > _spriteInkRight) _spriteInkRight = inkRight;
        }
      }
      if (width == 2) i++;
    }
    _flushSegment(canvas);
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset =
        offset.translate(length * _cellSize.width, _cellSize.height);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(
      Rect.fromPoints(offset, endOffset),
      paint,
    );
  }

  void paintKeywordForeground(
    Canvas canvas,
    Offset lineOffset,
    BufferLine line,
    int startCol,
    int endCol,
    Color fgColor,
  ) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;
    final colorKey = fgColor.toARGB32() << 21;

    for (var i = startCol; i < endCol && i < line.length; i++) {
      line.getCellData(i, cellData);
      final charCode = cellData.content & CellContent.codepointMask;
      final charWidth = cellData.content >> CellContent.widthShift;

      if (charCode != 0) {
        // Laid out once per (char, color): matches of a rule like "info" hit
        // most lines of a log flood.
        final key = charCode | colorKey;
        var cached = _keywordParagraphs[key];
        if (cached == null || cached.color != fgColor) {
          final style = _textStyle.toTextStyle(color: fgColor);
          final builder = ParagraphBuilder(style.getParagraphStyle())
            ..pushStyle(style.getTextStyle(textScaler: _textScaler))
            ..addText(String.fromCharCode(charCode));
          final para = builder.build()
            ..layout(ParagraphConstraints(width: cellWidth * 2));
          cached = _keywordParagraphs[key] = (color: fgColor, paragraph: para);
        }
        canvas.drawParagraph(
            cached.paragraph, lineOffset.translate(i * cellWidth, 0));
      }

      if (charWidth == 2) i++;
    }
  }

  /// Keyword foreground paragraphs by (char, color). Cleared with
  /// [_paragraphCache] (style, scale and font changes).
  final _keywordParagraphs =
      LruMap<int, ({Color color, Paragraph paragraph})>(maximumSize: 1024);

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line,
  ) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      final cellOffset = offset.translate(i * cellWidth, 0);

      paintCell(canvas, cellOffset, cellData);

      if (charWidth == 2) {
        i++;
      }
    }
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;
    // A plain space has no ink: skip the paragraph lookup and draw call (a
    // large share of cells in typical output). Underlined spaces still draw.
    if (charCode == 0x20 && cellData.flags & CellFlags.underline == 0) return;

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final cellFlags = cellData.flags;

      var color = cellFlags & CellFlags.inverse == 0
          ? resolveForegroundColor(cellData.foreground)
          : resolveBackgroundColor(cellData.background);

      if (cellData.flags & CellFlags.faint != 0) {
        color = color.withOpacity(0.5);
      }

      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: cellFlags & CellFlags.underline != 0,
      );

      // Flutter does not draw an underline below a space which is not between
      // other regular characters. As only single characters are drawn, this
      // will never produce an underline below a space in the terminal. As a
      // workaround the regular space CodePoint 0x20 is replaced with
      // the CodePoint 0xA0. This is a non breaking space and a underline can be
      // drawn below it.
      var char = String.fromCharCode(charCode);
      if (cellFlags & CellFlags.underline != 0 && charCode == 0x20) {
        char = String.fromCharCode(0xA0);
      }

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
