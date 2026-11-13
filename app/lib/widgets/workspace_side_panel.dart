// app/lib/widgets/workspace_side_panel.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Shared frame for right-side workspace panels (snippets, terminal config):
/// fixed width, card background, left border, and a header with a title,
/// optional extra header content (e.g. a search field), and a close button.
///
/// Rebuilds only when its owner does (layout / settings state), never on
/// terminal output; [debugBuildCount] lets a test assert that.
class WorkspaceSidePanel extends StatelessWidget {
  static const double panelWidth = 340;

  /// Debug-only build counter (asserts are stripped from release builds).
  @visibleForTesting
  static int debugBuildCount = 0;

  final String title;
  final String closeTooltip;
  final VoidCallback? onClose;
  final Widget? headerExtra;
  final Widget child;

  const WorkspaceSidePanel({
    super.key,
    required this.title,
    required this.closeTooltip,
    required this.child,
    this.onClose,
    this.headerExtra,
  });

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugBuildCount++;
      return true;
    }());
    return SizedBox(
      width: panelWidth,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: YsColors.card,
          border: Border(left: BorderSide(color: YsColors.border)),
        ),
        child: Column(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: YsColors.border)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    YsSpace.s3, YsSpace.s3, YsSpace.s3, YsSpace.s3),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YsColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (onClose != null)
                          Tooltip(
                            message: closeTooltip,
                            child: FButton.icon(
                              variant: .ghost,
                              size: .sm,
                              onPress: onClose,
                              child: const Icon(FLucideIcons.x),
                            ),
                          ),
                      ],
                    ),
                    if (headerExtra != null) ...[
                      const SizedBox(height: YsSpace.s2),
                      headerExtra!,
                    ],
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
