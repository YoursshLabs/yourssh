import 'package:xterm/xterm.dart' show CellAnchor;

class ShellCommand {
  ShellCommand(this._fallbackLine, {this.anchor});

  final int _fallbackLine;

  /// Buffer anchor on the prompt line. It moves with the line through scroll,
  /// insert/delete and scrollback trim, and detaches when the line is erased
  /// (ED 2 / ED 3) or dropped. Null only for markers created without a buffer
  /// (tests); those keep the fixed [_fallbackLine].
  final CellAnchor? anchor;

  /// Current absolute buffer line of this command's prompt (used by the
  /// gutter + jump). Only meaningful while [isLive].
  int get promptLine => anchor != null && anchor!.attached
      ? anchor!.y
      : _fallbackLine;

  /// False once the prompt line was erased or trimmed out of the buffer.
  bool get isLive {
    final a = anchor;
    if (a == null) return true;
    return a.attached && a.y >= 0;
  }

  /// Exit code, set when the command finishes (OSC 133;D). Null while pending.
  int? exitCode;

  /// null = pending/unknown · true = exit 0 · false = non-zero.
  bool? get succeeded => exitCode == null ? null : exitCode == 0;
}
