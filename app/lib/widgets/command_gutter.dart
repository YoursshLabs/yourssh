import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shell_integration_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// One paintable marker: an absolute buffer line + its success state.
typedef _Dot = ({int line, bool? ok});

/// Thin left strip drawing a status dot next to each command's prompt line.
/// Positions use the caller-supplied [lineHeight] (the terminal's per-line
/// pixel height, matching the scroll-offset unit). Repaints when the command
/// set or any status changes, and as the view scrolls.
///
/// Marker lines come from buffer anchors, so they follow their lines through
/// scrollback trimming and disappear when the line is erased (clear).
class CommandGutter extends StatelessWidget {
  const CommandGutter({
    super.key,
    required this.sessionId,
    required this.scrollController,
    required this.lineHeight,
    this.width = 8,
    this.onJumpTo,
  });

  final String sessionId;
  final ScrollController scrollController;
  final double lineHeight;
  final double width;
  final void Function(int promptLine)? onJumpTo;

  @override
  Widget build(BuildContext context) {
    // Rebuild only when THIS session changes: the provider notifies globally,
    // select scopes us to our own session's revision.
    context.select<ShellIntegrationProvider, int>((p) => p.revisionFor(sessionId));
    final state = context.read<ShellIntegrationProvider>().maybeStateFor(sessionId);
    if (state == null || state.commands.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: AnimatedBuilder(
        animation: scrollController,
        builder: (context, _) {
          // Snapshot to immutable records on every scroll tick: marker lines
          // are anchored in the terminal buffer, so reading them here keeps
          // the dots on their rows (and drops those whose line was erased).
          // The painter compares against a fresh snapshot, not shared state.
          final dots = <_Dot>[
            for (final c in state.liveCommands)
              (line: c.promptLine, ok: c.succeeded),
          ];
          final offset =
              scrollController.hasClients ? scrollController.offset : 0.0;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: onJumpTo == null
                ? null
                : (d) {
                    final line =
                        ((d.localPosition.dy + offset) / lineHeight).round();
                    _Dot? best;
                    for (final dot in dots) {
                      if (best == null ||
                          (dot.line - line).abs() < (best.line - line).abs()) {
                        best = dot;
                      }
                    }
                    // Only jump when the tap is actually on/near a dot row, so
                    // brushing the strip far from any command doesn't snap.
                    if (best != null && (best.line - line).abs() <= 1) {
                      onJumpTo!(best.line);
                    }
                  },
            child: CustomPaint(
              painter: _GutterPainter(dots, offset, lineHeight),
              size: Size(width, double.infinity),
            ),
          );
        },
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter(this.dots, this.scrollOffset, this.lineHeight);
  final List<_Dot> dots;
  final double scrollOffset;
  final double lineHeight;

  static const _green = YsColors.ok;
  static const _red = YsColors.error;
  static const _grey = YsColors.off;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final dot in dots) {
      final y = dot.line * lineHeight - scrollOffset + lineHeight / 2;
      if (y < -lineHeight || y > size.height + lineHeight) continue;
      paint.color = switch (dot.ok) {
        true => _green,
        false => _red,
        null => _grey,
      };
      canvas.drawCircle(Offset(size.width / 2, y), 3, paint);
    }
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.lineHeight != lineHeight ||
      !listEquals(old.dots, dots);
}
