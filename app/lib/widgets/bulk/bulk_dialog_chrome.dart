import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Shared chrome of the bulk Run-command and Push-files dialogs: header bar,
/// footer bar and a size that shrinks to fit small windows.

/// Header bar: icon, [title] (ellipsized) and a tooltipped close button.
class BulkDialogHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onClose;
  const BulkDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
    decoration: const BoxDecoration(
      color: YsColors.sidebar,
      border: Border(bottom: BorderSide(color: YsColors.border)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: YsColors.mutedForeground),
        const SizedBox(width: YsSpace.s2),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: YsColors.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Tooltip(
          message: 'Close',
          excludeFromSemantics: true,
          child: FButton.icon(
            variant: .ghost,
            size: .xs,
            semanticsLabel: 'Close',
            onPress: onClose,
            child: const Icon(FLucideIcons.x),
          ),
        ),
      ],
    ),
  );
}

/// Footer bar: optional [summary] on the left, CLOSE on the right.
class BulkDialogFooter extends StatelessWidget {
  final String? summary;
  final VoidCallback onClose;
  const BulkDialogFooter({super.key, this.summary, required this.onClose});

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
    decoration: const BoxDecoration(
      color: YsColors.sidebar,
      border: Border(top: BorderSide(color: YsColors.border)),
    ),
    child: Row(
      children: [
        if (summary != null)
          Expanded(
            child: Text(
              summary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 11,
              ),
            ),
          )
        else
          const Spacer(),
        FButton(
          variant: .outline,
          size: .xs,
          mainAxisSize: MainAxisSize.min,
          onPress: onClose,
          child: const Text('CLOSE'),
        ),
      ],
    ),
  );
}

/// Sizes a dialog body to [width] x [height], shrinking to the room the
/// dialog frame leaves in small windows (900x600 desktop minimum).
class BulkDialogBody extends StatelessWidget {
  final double width;
  final double height;
  final Widget child;
  const BulkDialogBody({
    super.key,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SizedBox(
      width: width.clamp(0.0, c.maxWidth),
      height: height.clamp(0.0, c.maxHeight),
      child: child,
    ),
  );
}
