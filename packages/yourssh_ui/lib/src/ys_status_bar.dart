import 'package:flutter/material.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// The bottom status line of a terminal or remote-desktop workspace: a 22 px
/// `chrome` strip with [leading] fields from the left and [trailing] fields
/// against the right edge, in 11 px monospace.
///
/// Purely presentational. Callers decide what to show and when to rebuild;
/// keep live values (timers, sizes) in their own small widgets so the bar is
/// not rebuilt for them. Content that does not fit is clipped, never
/// overflowed: trailing fields keep at most 60% of the width and leading
/// fields take the rest.
class YsStatusBar extends StatelessWidget {
  /// Height of the strip.
  static const double height = 22;

  final List<Widget> leading;
  final List<Widget> trailing;

  const YsStatusBar({
    super.key,
    required this.leading,
    this.trailing = const [],
  });

  static const TextStyle _textStyle = TextStyle(
    color: YsColors.mutedForeground,
    fontSize: 11,
    height: 1.2,
    fontFamily: kYsMonoFontFamily,
    fontFamilyFallback: kYsMonoFontFallback,
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ColoredBox(
      key: const Key('ys-status-bar'),
      color: YsColors.chrome,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: YsColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
          child: DefaultTextStyle(
            style: _textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: IconTheme.merge(
              data: const IconThemeData(
                size: 12,
                color: YsColors.mutedForeground,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(child: _Clipped(children: leading)),
                    if (trailing.isNotEmpty) ...[
                      const SizedBox(width: YsSpace.s3),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.6,
                        ),
                        child: _Clipped(children: trailing, reverse: true),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A row of fields separated by [YsSpace.s3] that clips when too wide.
/// [reverse] keeps the end visible (right-aligned content).
class _Clipped extends StatelessWidget {
  final List<Widget> children;
  final bool reverse;
  const _Clipped({required this.children, this.reverse = false});

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: reverse,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: YsSpace.s3),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// One [YsStatusBar] field: an optional 6 px status dot in [dotColor] or an
/// [icon], then [label] on one line, capped at [maxLabelWidth] with an
/// ellipsis. [color] tints the label (and the icon); [tooltip] explains it.
class YsStatusItem extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? dotColor;
  final Color? color;
  final String? tooltip;
  final double maxLabelWidth;

  const YsStatusItem({
    super.key,
    required this.label,
    this.icon,
    this.dotColor,
    this.color,
    this.tooltip,
    this.maxLabelWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    final item = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dotColor != null) ...[
          SizedBox.square(
            dimension: 6,
            child: DecoratedBox(
              key: const Key('ys-status-dot'),
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: YsSpace.s1 + 2),
        ] else if (icon != null) ...[
          Icon(icon, color: color),
          const SizedBox(width: YsSpace.s1),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxLabelWidth),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
    final msg = tooltip;
    return msg == null || msg.isEmpty
        ? item
        : Tooltip(message: msg, child: item);
  }
}
