import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// What to rasterize for one atlas tile. [key] is the caller's packed cache
/// key; the other fields are what it encodes, kept for rendering.
class GlyphSpec {
  GlyphSpec({
    required this.key,
    required this.codePoint,
    required this.style,
    required this.color,
    required this.phase,
    required this.yFraction,
  });

  final int key;
  final int codePoint;

  /// Caller-defined style bits (bold / italic / underline ...).
  final int style;

  /// Exact paint color of the glyph. Tiles are rendered per color: tinting
  /// one white mask cannot reproduce Skia's luminance-dependent text gamma.
  final ui.Color color;

  /// Horizontal subpixel phase, 0..3 (quarter device pixels).
  final int phase;

  /// Fractional part of the device-space y where the glyph's paragraph is
  /// drawn. The engine snaps glyphs vertically relative to it.
  final double yFraction;
}

/// An admitted glyph: where its ink sits in the atlas page and where it goes
/// relative to the glyph origin.
class AtlasGlyph {
  const AtlasGlyph._(
      this.left, this.top, this.right, this.bottom, this.dx, this.dy);

  /// A glyph without ink (e.g. a space with an empty underline).
  static const empty = AtlasGlyph._(0, 0, 0, 0, 0, 0);

  /// Source rect of the ink box in the page, in device pixels.
  final double left, top, right, bottom;

  /// Top-left of the ink box relative to the device pixel the glyph origin
  /// snaps to: x relative to `floor(originX + 1/8)`, y relative to the
  /// integer part of the paragraph's device y.
  final int dx, dy;

  bool get isEmpty => right == left;

  /// Exclusive right edge of the ink, relative to the snapped origin.
  int get inkRight => dx + (right - left).toInt();
}

/// Builds the paragraph a tile is rendered from (the exact one the paragraph
/// path would draw for that cell).
typedef GlyphParagraphBuilder = ui.Paragraph Function(GlyphSpec spec);

/// A glyph atlas for the terminal's text: each (glyph, style, color, subpixel
/// phase, vertical fraction) is rendered once with the regular paragraph code
/// into a single atlas page, and lines then draw runs of cells with
/// `Canvas.drawRawAtlas` instead of one `drawParagraph` per cell.
///
/// Admission is asynchronous: a missing glyph is requested and the caller
/// draws it with a paragraph meanwhile. A batch of requests is rendered into
/// a staging image with generous slots and read back; the readback gives each
/// tile's ink bounds (so only ink is copied and drawn, and the painter can
/// keep background/glyph ordering exact) and rejects glyphs the atlas cannot
/// reproduce: ink reaching the slot border, or color glyphs (any pixel that
/// is not the paint color times coverage — emoji). Admitted ink is packed
/// into a new page image (`toImageSync`: old page + new tiles), every entry
/// keeps its position, [generation] is bumped and [onChanged] fires so cached
/// pictures holding the old page are dropped.
class GlyphAtlas {
  GlyphAtlas({required this.buildParagraph, this.onChanged});

  final GlyphParagraphBuilder buildParagraph;

  /// Called after a batch changed the page (new glyphs admitted / reset).
  void Function()? onChanged;

  static const _pageWidth = 2048;
  static const _maxPageHeight = 2048;
  static const _maxBatch = 256;
  static const _maxRequested = 4096;

  /// After a full page was reset, another reset within this window freezes
  /// admission instead (a stream of ever new colors would otherwise turn
  /// into a render/readback loop that only costs time).
  static const _resetCooldownMs = 10000;

  double _dpr = 1;
  int _cellWidth = 1; // device px, ceiled
  int _cellHeight = 1;

  final _glyphs = HashMap<int, AtlasGlyph>();
  final _rejected = HashSet<int>();
  final _requested = LinkedHashMap<int, GlyphSpec>();

  ui.Image? _page;
  int _shelfX = 0;
  int _shelfY = 0;
  int _shelfHeight = 0;

  /// Bumped whenever [page] or the glyph set changes.
  int get generation => _generation;
  int _generation = 0;

  /// Bumped by [reset]; a batch started before a reset is discarded.
  int _epoch = 0;

  bool _scheduled = false;
  bool _busy = false;
  bool _disposed = false;
  final _idleWaiters = <Completer<void>>[];

  final _clock = Stopwatch()..start();
  int _lastResetMs = -_resetCooldownMs;
  int _frozenUntilMs = 0;

  /// The current page. Non-null whenever [lookup] returned a non-empty glyph.
  ui.Image? get page => _page;

  /// Number of admitted glyphs (including ink-less ones).
  int get length => _glyphs.length;

  AtlasGlyph? lookup(int key) => _glyphs[key];

  /// Whether [request] would queue [key] (lets callers skip building a
  /// [GlyphSpec] for glyphs that are rejected, queued or not admissible now).
  bool shouldRequest(int key) =>
      !_disposed &&
      !_rejected.contains(key) &&
      !_requested.containsKey(key) &&
      _requested.length < _maxRequested &&
      _clock.elapsedMilliseconds >= _frozenUntilMs;

  void request(GlyphSpec spec) {
    if (!shouldRequest(spec.key)) return;
    _requested[spec.key] = spec;
    _schedule();
  }

  /// Drops every glyph (new device pixel ratio, cell size, font...).
  void configure(double devicePixelRatio, ui.Size cellSize) {
    _dpr = devicePixelRatio;
    _cellWidth = math.max(1, (cellSize.width * devicePixelRatio).ceil());
    _cellHeight = math.max(1, (cellSize.height * devicePixelRatio).ceil());
    reset();
  }

  void reset() {
    _epoch++;
    _glyphs.clear();
    _rejected.clear();
    _requested.clear();
    _page?.dispose();
    _page = null;
    _shelfX = _shelfY = _shelfHeight = 0;
    _generation++;
    _notifyIdle();
  }

  void dispose() {
    _disposed = true;
    reset();
  }

  /// Completes once no request is queued or being rendered.
  Future<void> whenIdle() {
    if (_isIdle) return Future.value();
    final completer = Completer<void>();
    _idleWaiters.add(completer);
    return completer.future;
  }

  bool get _isIdle => !_busy && !_scheduled && _requested.isEmpty;

  void _notifyIdle() {
    if (!_isIdle || _idleWaiters.isEmpty) return;
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }

  void _schedule() {
    if (_scheduled || _busy || _disposed) return;
    _scheduled = true;
    // After the current frame: requests come from paint.
    scheduleMicrotask(_runBatch);
  }

  // Slot geometry of the staging image: room for a double-width glyph plus a
  // cell of overhang on every side; the glyph origin snaps to (_slotX, _slotY).
  int get _slotWidth => _cellWidth * 4 + 4;
  int get _slotHeight => _cellHeight * 2 + 4;
  int get _slotX => _cellWidth + 2;
  int get _slotY => _cellHeight ~/ 2 + 2;

  Future<void> _runBatch() async {
    _scheduled = false;
    if (_disposed || _busy) return;
    if (_requested.isEmpty) {
      _notifyIdle();
      return;
    }
    _busy = true;
    final epoch = _epoch;
    final specs = <GlyphSpec>[];
    for (final key in _requested.keys.take(_maxBatch).toList()) {
      specs.add(_requested.remove(key)!);
    }

    final slotW = _slotWidth;
    final slotH = _slotHeight;
    final columns = math.max(1, math.min(specs.length, 4096 ~/ slotW));
    final rows = (specs.length + columns - 1) ~/ columns;
    final width = columns * slotW;
    final height = rows * slotH;

    ui.Picture? picture;
    ui.Image? staging;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (var i = 0; i < specs.length; i++) {
        final spec = specs[i];
        final paragraph = buildParagraph(spec);
        canvas.save();
        canvas.translate(
          (i % columns) * slotW + _slotX + spec.phase / 4,
          (i ~/ columns) * slotH + _slotY + spec.yFraction,
        );
        canvas.scale(_dpr);
        canvas.drawParagraph(paragraph, ui.Offset.zero);
        canvas.restore();
        paragraph.dispose();
      }
      picture = recorder.endRecording();
      staging = await picture.toImage(width, height);
      final bytes = await staging.toByteData();
      if (bytes != null && epoch == _epoch && !_disposed) {
        _admit(specs, staging, bytes, columns);
      }
    } catch (_) {
      // Rendering failed (e.g. no GPU context): these glyphs keep using
      // paragraphs.
      if (epoch == _epoch) {
        for (final spec in specs) {
          _rejected.add(spec.key);
        }
      }
    } finally {
      picture?.dispose();
      staging?.dispose();
      _busy = false;
      if (_requested.isNotEmpty && !_disposed) {
        _schedule();
      } else {
        _notifyIdle();
      }
    }
  }

  void _admit(
    List<GlyphSpec> specs,
    ui.Image staging,
    ByteData bytes,
    int columns,
  ) {
    final slotW = _slotWidth;
    final slotH = _slotHeight;
    final stride = columns * slotW;
    final pixels = bytes.buffer.asUint32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    final rgba = bytes.buffer.asUint8List(bytes.offsetInBytes);

    final placed = <_Placement>[];
    for (var i = 0; i < specs.length; i++) {
      final spec = specs[i];
      final x0 = (i % columns) * slotW;
      final y0 = (i ~/ columns) * slotH;
      var minX = slotW, minY = slotH, maxX = -1, maxY = -1;
      for (var y = 0; y < slotH; y++) {
        final row = (y0 + y) * stride + x0;
        for (var x = 0; x < slotW; x++) {
          // rawRgba, little endian: alpha is the top byte.
          if (pixels[row + x] >> 24 != 0) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            maxY = y;
          }
        }
      }
      if (maxX < 0) {
        _glyphs[spec.key] = AtlasGlyph.empty;
        continue;
      }
      if (minX == 0 || minY == 0 || maxX == slotW - 1 || maxY == slotH - 1) {
        _rejected.add(spec.key); // ink may continue outside the slot
        continue;
      }
      if (!_isPaintColored(rgba, stride, x0 + minX, y0 + minY, x0 + maxX,
          y0 + maxY, spec.color)) {
        _rejected.add(spec.key); // color glyph (emoji)
        continue;
      }
      placed.add(_Placement(
        spec.key,
        x0 + minX,
        y0 + minY,
        maxX - minX + 1,
        maxY - minY + 1,
        minX - _slotX,
        minY - _slotY,
      ));
    }

    if (placed.isNotEmpty) {
      if (!_pack(placed)) {
        final now = _clock.elapsedMilliseconds;
        if (now - _lastResetMs < _resetCooldownMs) {
          // Full again shortly after a reset: stop admitting for a while.
          _frozenUntilMs = now + _resetCooldownMs;
          _requested.clear();
          return;
        }
        _lastResetMs = now;
        _glyphs.clear();
        _page?.dispose();
        _page = null;
        _shelfX = _shelfY = _shelfHeight = 0;
        if (!_pack(placed)) {
          for (final p in placed) {
            _rejected.add(p.key);
          }
          placed.clear();
        }
      }
    }

    if (placed.isNotEmpty) {
      final height = _shelfY + _shelfHeight;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()
        ..filterQuality = ui.FilterQuality.none
        ..isAntiAlias = false;
      final old = _page;
      if (old != null) canvas.drawImage(old, ui.Offset.zero, paint);
      for (final p in placed) {
        canvas.drawImageRect(
          staging,
          ui.Rect.fromLTWH(p.sx.toDouble(), p.sy.toDouble(), p.width.toDouble(),
              p.height.toDouble()),
          ui.Rect.fromLTWH(p.px.toDouble(), p.py.toDouble(),
              p.width.toDouble(), p.height.toDouble()),
          paint,
        );
      }
      final picture = recorder.endRecording();
      final page = picture.toImageSync(_pageWidth, height);
      picture.dispose();
      old?.dispose();
      _page = page;
      for (final p in placed) {
        _glyphs[p.key] = AtlasGlyph._(
          p.px.toDouble(),
          p.py.toDouble(),
          (p.px + p.width).toDouble(),
          (p.py + p.height).toDouble(),
          p.dx,
          p.dy,
        );
      }
    }
    _generation++;
    onChanged?.call();
  }

  /// Shelf-packs [placed] into the page (1 px gutters); false when full.
  /// Positions are only committed when everything fits.
  bool _pack(List<_Placement> placed) {
    placed.sort((a, b) => b.height.compareTo(a.height));
    var x = _shelfX, y = _shelfY, shelf = _shelfHeight;
    for (final p in placed) {
      if (x + p.width > _pageWidth) {
        y += shelf + 1;
        x = 0;
        shelf = 0;
      }
      if (p.width > _pageWidth || y + p.height > _maxPageHeight) return false;
      p.px = x;
      p.py = y;
      x += p.width + 1;
      if (p.height > shelf) shelf = p.height;
    }
    _shelfX = x;
    _shelfY = y;
    _shelfHeight = shelf;
    return true;
  }

  /// Whether every inked pixel in the box is [color] scaled by coverage
  /// (premultiplied), i.e. a plain glyph mask in the paint color.
  static bool _isPaintColored(Uint8List rgba, int stride, int left, int top,
      int right, int bottom, ui.Color color) {
    final r = color.r * 255, g = color.g * 255, b = color.b * 255;
    for (var y = top; y <= bottom; y++) {
      for (var x = left; x <= right; x++) {
        final i = (y * stride + x) * 4;
        final a = rgba[i + 3];
        if (a == 0) continue;
        final k = a / 255;
        if ((rgba[i] - r * k).abs() > 3 ||
            (rgba[i + 1] - g * k).abs() > 3 ||
            (rgba[i + 2] - b * k).abs() > 3) {
          return false;
        }
      }
    }
    return true;
  }
}

class _Placement {
  _Placement(this.key, this.sx, this.sy, this.width, this.height, this.dx,
      this.dy);

  final int key;
  final int sx, sy, width, height, dx, dy;
  int px = 0, py = 0;
}
