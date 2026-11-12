import 'package:flutter/material.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// Host card chrome (see B-1-hosts mockup). Presentational: callers own state.
/// Radius 10, `card` background, `border`; selected = 1 px `primary` border;
/// hover = `secondary` background.
class YsHostCard extends StatefulWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? statusDot;
  final List<Widget> badges;
  final List<Widget> tags;
  final String? meta;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset)? onSecondaryTap;
  final VoidCallback? onLongPress;
  final Widget? trailingAction;

  const YsHostCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.statusDot,
    this.badges = const [],
    this.tags = const [],
    this.meta,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.trailingAction,
  });

  @override
  State<YsHostCard> createState() => _YsHostCardState();
}

class _YsHostCardState extends State<YsHostCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hasChips = w.tags.isNotEmpty || w.meta != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: w.onTap,
        onDoubleTap: w.onDoubleTap,
        onLongPress: w.onLongPress,
        onSecondaryTapUp: w.onSecondaryTap == null
            ? null
            : (d) => w.onSecondaryTap!(d.globalPosition),
        child: Container(
          key: const Key('ys-host-card-box'),
          padding: const EdgeInsets.all(YsSpace.s3),
          decoration: BoxDecoration(
            color: _hovered ? YsColors.secondary : YsColors.card,
            borderRadius: BorderRadius.circular(YsRadius.card),
            border: Border.all(
              color: w.selected ? YsColors.primary : YsColors.border,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              w.leading,
              const SizedBox(width: YsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            w.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YsColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (w.statusDot != null) ...[
                          const SizedBox(width: YsSpace.s2),
                          w.statusDot!,
                        ],
                        for (final b in w.badges) ...[
                          const SizedBox(width: YsSpace.s2),
                          b,
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      w.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: YsColors.mutedForeground,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (hasChips) ...[
                      const SizedBox(height: YsSpace.s2),
                      Wrap(
                        spacing: YsSpace.s1 + 2,
                        runSpacing: YsSpace.s1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ...w.tags,
                          if (w.meta != null)
                            Text(
                              w.meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: YsColors.mutedForeground,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (w.trailingAction != null) ...[
                const SizedBox(width: YsSpace.s2),
                w.trailingAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
