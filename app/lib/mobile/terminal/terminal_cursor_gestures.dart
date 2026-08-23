import 'package:xterm/xterm.dart';

/// Translates a long-press drag into a stream of arrow-key presses, the
/// touch way to move the terminal cursor. Distance is accumulated; every
/// `step` pixels in the dominant axis emits one arrow key. The step shrinks
/// across three gears the longer a single drag persists, so a slow nudge moves
/// one cell while a long sweep flies. Pure + deterministic for unit testing;
/// call [reset] when the drag ends.
class CursorDragMapper {
  final double baseStep;
  CursorDragMapper({this.baseStep = 22});

  double _accX = 0;
  double _accY = 0;
  int _emitted = 0;

  double get _step {
    if (_emitted >= 12) return baseStep * 0.4; // gear 3
    if (_emitted >= 5) return baseStep * 0.65; // gear 2
    return baseStep; // gear 1
  }

  List<TerminalKey> addDelta(double dx, double dy) {
    _accX += dx;
    _accY += dy;
    final keys = <TerminalKey>[];
    while (true) {
      final step = _step;
      final xReady = _accX.abs() >= step;
      final yReady = _accY.abs() >= step;
      if (!xReady && !yReady) break;
      final useX = xReady && (!yReady || _accX.abs() >= _accY.abs());
      if (useX) {
        keys.add(_accX > 0 ? TerminalKey.arrowRight : TerminalKey.arrowLeft);
        _accX += _accX > 0 ? -step : step;
      } else {
        keys.add(_accY > 0 ? TerminalKey.arrowDown : TerminalKey.arrowUp);
        _accY += _accY > 0 ? -step : step;
      }
      _emitted++;
    }
    return keys;
  }

  void reset() {
    _accX = 0;
    _accY = 0;
    _emitted = 0;
  }
}
