import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shell_integration_provider.dart';

/// One paintable marker: an absolute buffer line + its success state.
typedef _Dot = ({int line, bool? ok});

/// Thin left strip drawing a status dot next to each command's prompt line.
/// Positions use the caller-supplied [lineHeight] (the terminal's per-line
/// pixel height, matching the scroll-offset unit). Repaints when the command
/// set or any status changes, and as the view scrolls.
///
/// Known limitation: [promptLine] is an absolute buffer index captured at
/// marker time. After the terminal's scrollback cap (maxLines) starts trimming
/// old lines, those indices drift relative to the rendered content, so dots for
/// very old commands in a >maxLines session may sit a few rows off. Off-screen
/// dots are culled, so the impact is bounded.
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
    final commands =
        context.read<ShellIntegrationProvider>().maybeStateFor(sessionId)?.commands;
    if (commands == null || commands.isEmpty) return const SizedBox.shrink();
    // Snapshot to immutable records each build. The provider mutates the same
    // List/ShellCommand instances in place, so the painter must compare against
    // a fresh snapshot (not the shared list) to detect status/append changes.
    final dots = <_Dot>[
      for (final c in commands) (line: c.promptLine, ok: c.succeeded),
    ];
    return SizedBox(
      width: width,
      child: AnimatedBuilder(
        animation: scrollController,
        builder: (context, _) {
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

  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _grey = Color(0xFF6B7280);

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
