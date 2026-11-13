import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Icon-only action button used by the container screens. The tooltip doubles
/// as the semantics label, and the button stays keyboard-focusable.
class ContainerIconAction extends StatelessWidget {
  const ContainerIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPress,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: FButton.icon(
      variant: .ghost,
      size: .xs,
      semanticsLabel: tooltip,
      onPress: onPress,
      child: Icon(icon, color: active ? YsColors.primary : null),
    ),
  );
}

/// Small ghost text button (Clear, Up, Down, Open, Stop...).
class ContainerTextAction extends StatelessWidget {
  const ContainerTextAction({
    super.key,
    required this.label,
    required this.onPress,
  });

  final String label;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => FButton(
    variant: .ghost,
    size: .xs,
    mainAxisSize: MainAxisSize.min,
    onPress: onPress,
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

class ContainerSpinner extends StatelessWidget {
  const ContainerSpinner({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: const FCircularProgress());
}

/// Two-line list row: ellipsizing title and subtitle with a trailing action
/// cluster. Rows live in a bordered list; [highlighted] marks the row whose
/// logs are open.
class ContainerRow extends StatelessWidget {
  const ContainerRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.highlighted = false,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: highlighted ? YsColors.primary : Colors.transparent,
          width: 3,
        ),
        bottom: const BorderSide(color: YsColors.border),
      ),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: YsSpace.s3,
      vertical: YsSpace.s1,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: YsSpace.s2),
        trailing,
      ],
    ),
  );
}

/// Log viewer: header (icon, [title], optional Clear, Close) and mono lines.
class ContainerLogPanel extends StatelessWidget {
  const ContainerLogPanel({
    super.key,
    required this.title,
    required this.lines,
    required this.controller,
    required this.onClose,
    this.onClear,
    this.spinnerWhenEmpty = false,
  });

  final String title;
  final List<String> lines;
  final ScrollController controller;
  final VoidCallback onClose;
  final VoidCallback? onClear;

  /// Show a spinner while no line has arrived yet (Kubernetes log stream).
  final bool spinnerWhenEmpty;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        color: YsColors.card,
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s3,
          vertical: YsSpace.s1,
        ),
        child: Row(
          children: [
            const Icon(
              FLucideIcons.fileText,
              size: 14,
              color: YsColors.mutedForeground,
            ),
            const SizedBox(width: YsSpace.s2 - 2),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: YsColors.mutedForeground,
                ),
              ),
            ),
            if (onClear != null)
              ContainerTextAction(label: 'Clear', onPress: onClear),
            ContainerIconAction(
              icon: FLucideIcons.x,
              tooltip: 'Close logs',
              onPress: onClose,
            ),
          ],
        ),
      ),
      Expanded(
        child: lines.isEmpty && spinnerWhenEmpty
            ? const Center(child: ContainerSpinner(size: 16))
            : ListView.builder(
                controller: controller,
                padding: const EdgeInsets.all(YsSpace.s2),
                itemCount: lines.length,
                itemBuilder: (_, i) => Text(
                  lines[i],
                  style: const TextStyle(
                    fontFamily: kYsMonoFontFamily,
                    fontSize: 11,
                    color: YsColors.foreground,
                  ),
                ),
              ),
      ),
    ],
  );
}
