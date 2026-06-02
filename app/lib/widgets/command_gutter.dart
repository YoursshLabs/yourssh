import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/shell_command.dart';
import '../providers/shell_integration_provider.dart';

/// Thin left strip drawing a status dot next to each command's prompt line.
/// Aligns to the same line→pixel math the terminal scroll uses
/// (lineHeight = fontSize * 1.35) and repaints as the view scrolls.
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
    final commands = context
            .watch<ShellIntegrationProvider>()
            .maybeStateFor(sessionId)
            ?.commands ??
        const <ShellCommand>[];
    if (commands.isEmpty) return const SizedBox.shrink();
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
                    final line = ((d.localPosition.dy + offset) / lineHeight)
                        .round();
                    ShellCommand? best;
                    for (final c in commands) {
                      if (best == null ||
                          (c.promptLine - line).abs() <
                              (best.promptLine - line).abs()) {
                        best = c;
                      }
                    }
                    if (best != null) onJumpTo!(best.promptLine);
                  },
            child: CustomPaint(
              painter: _GutterPainter(commands, offset, lineHeight),
              size: Size(width, double.infinity),
            ),
          );
        },
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter(this.commands, this.scrollOffset, this.lineHeight);
  final List<ShellCommand> commands;
  final double scrollOffset;
  final double lineHeight;

  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _grey = Color(0xFF6B7280);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final c in commands) {
      final y = c.promptLine * lineHeight - scrollOffset + lineHeight / 2;
      if (y < -lineHeight || y > size.height + lineHeight) continue;
      paint.color = switch (c.succeeded) {
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
      old.commands.length != commands.length ||
      old.lineHeight != lineHeight;
}
