import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/keyword_highlight.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// A recorded picture of one buffer line (text + keyword highlights), painted
/// at origin, valid for a specific [BufferLine.version].
class _LinePicture {
  _LinePicture(this.picture, this.version);

  final Picture picture;
  final int version;
}

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

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
    _invalidateLinePictures();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _invalidateLinePictures();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
    _invalidateLinePictures();
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
    _invalidateLinePictures();
  }

  /// Returns a picture that paints [line] (text and keyword highlights) at
  /// origin. Cached: the line is re-recorded only when its content version
  /// changed since the last paint.
  Picture getLinePicture(BufferLine line) {
    // Remove + reinsert keeps the map insertion-ordered by recency (LRU).
    final cached = _linePictures.remove(line);
    if (cached != null && cached.version == line.version) {
      _linePictures[line] = cached;
      return cached.picture;
    }
    cached?.picture.dispose();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    paintLine(canvas, Offset.zero, line);
    _paintLineKeywords(canvas, line);
    final picture = recorder.endRecording();

    _linePictures[line] = _LinePicture(picture, line.version);
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

    for (var i = startCol; i < endCol && i < line.length; i++) {
      line.getCellData(i, cellData);
      final charCode = cellData.content & CellContent.codepointMask;
      final charWidth = cellData.content >> CellContent.widthShift;

      if (charCode != 0) {
        final style = _textStyle.toTextStyle(color: fgColor);
        final builder = ParagraphBuilder(style.getParagraphStyle())
          ..pushStyle(style.getTextStyle(textScaler: _textScaler))
          ..addText(String.fromCharCode(charCode));
        final para = builder.build()
          ..layout(ParagraphConstraints(width: cellWidth * 2));
        canvas.drawParagraph(para, lineOffset.translate(i * cellWidth, 0));
        para.dispose();
      }

      if (charWidth == 2) i++;
    }
  }

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
