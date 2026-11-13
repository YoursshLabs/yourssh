import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Slim header of an RDP/VNC workspace: the tab label on the left (ellipsised
/// so a long host label never overflows) and [actions] on the right.
class RemoteWorkspaceToolbar extends StatelessWidget {
  final String label;
  final List<Widget> actions;
  const RemoteWorkspaceToolbar({
    super.key,
    required this.label,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s2),
      decoration: const BoxDecoration(
        color: YsColors.card,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YsColors.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Icon-only toolbar/pill button; always carries a [tooltip]. A null
/// [onPressed] renders it disabled.
class RemoteIconAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const RemoteIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FButton.icon(
        variant: .ghost,
        size: .sm,
        onPress: onPressed,
        child: Icon(icon, size: 16),
      ),
    );
  }
}

/// Floating fullscreen pill surface (revealed from the top screen edge).
class RemoteFloatingPill extends StatelessWidget {
  final List<Widget> children;
  const RemoteFloatingPill({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: YsColors.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(YsRadius.card),
        border: Border.all(color: YsColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s2,
          vertical: YsSpace.s1 / 2,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Centered status line / error message + optional Retry for the overlays.
class RemoteStatusOverlay extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool showRetry;
  const RemoteStatusOverlay({
    super.key,
    required this.message,
    this.onRetry,
    this.showRetry = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(YsSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: YsColors.mutedForeground),
            ),
            if (showRetry) ...[
              const SizedBox(height: YsSpace.s3),
              // FButton fills the width it is given unless told to shrink.
              FButton(
                mainAxisSize: MainAxisSize.min,
                onPress: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
