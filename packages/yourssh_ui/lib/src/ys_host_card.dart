import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// Host card chrome (see B-1-hosts mockup). Presentational: callers own state.
/// Radius 10, `card` background, `border`; selected = 1 px `primary` border;
/// hover = `secondary` background; keyboard focus draws a 2 px `primary` ring.
///
/// Note: passing [onDoubleTap] makes the gesture arena wait, so [onTap] is
/// delayed by `kDoubleTapTimeout` (300 ms).
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hasChips = w.tags.isNotEmpty || w.meta != null;
    final tappable = w.onTap != null;
    return Semantics(
      button: true,
      container: true,
      selected: w.selected,
      label: '${w.title}, ${w.subtitle}',
      onTap: w.onTap,
      child: FocusableActionDetector(
        enabled: tappable,
        mouseCursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
        onFocusChange: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              w.onTap?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
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
                  color: w.selected || _focused
                      ? YsColors.primary
                      : YsColors.border,
                  width: _focused ? 2 : 1,
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
                        Wrap(
                          spacing: YsSpace.s2,
                          runSpacing: YsSpace.s1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              w.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: YsColors.foreground,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (w.statusDot != null) w.statusDot!,
                            ...w.badges,
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
                            fontFamily: kYsMonoFontFamily,
                            fontFamilyFallback: kYsMonoFontFallback,
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
        ),
      ),
    );
  }
}
