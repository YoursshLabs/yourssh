import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';

/// Visual chrome of one browser-style tab. Purely presentational: callers own
/// state and behaviour (selection, rename, close, context menu).
///
/// Active: `card` background, 2 px `primary` bottom indicator
/// (`Key('ys-tab-indicator')`), foreground text. Inactive: `chrome`
/// background, muted text, `secondary` on hover. The close button shows on
/// hover, keyboard focus (on the tab or its close button) or when active; while
/// hidden it is inert (no pointer, no semantics) but still reachable by Tab once
/// the tab has focus. The tab is focusable: Enter / Space selects it.
class YsTab extends StatefulWidget {
  final Widget label;
  final Widget? leading;
  final List<Widget> trailing;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onMiddleClick;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final VoidCallback? onClose;
  final String? closeTooltip;

  /// Optional colour tag, rendered as a small dot before the label.
  final Color? colorTag;

  static const double height = 38;

  const YsTab({
    super.key,
    required this.label,
    this.leading,
    this.trailing = const [],
    required this.active,
    this.onTap,
    this.onDoubleTap,
    this.onMiddleClick,
    this.onSecondaryTap,
    this.onClose,
    this.closeTooltip,
    this.colorTag,
  });

  @override
  State<YsTab> createState() => _YsTabState();
}

class _YsTabState extends State<YsTab> {
  bool _hovered = false;
  bool _focusWithin = false;
  bool _focusSelf = false;
  late final FocusNode _focusNode = FocusNode(debugLabel: 'YsTab');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      final self = _focusNode.hasPrimaryFocus;
      if (_focusSelf != self && mounted) setState(() => _focusSelf = self);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Only act while the tab itself is focused, not its close button.
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final k = event.logicalKey;
    if ((k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.space) &&
        widget.onTap != null) {
      widget.onTap!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final bg = active
        ? YsColors.card
        : _hovered
        ? YsColors.secondary
        : YsColors.chrome;
    final fg = active ? YsColors.foreground : YsColors.mutedForeground;
    final showClose = _hovered || _focusWithin || active;
    final showRing =
        _focusSelf &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        onFocusChange: (f) {
          if (_focusWithin != f) setState(() => _focusWithin = f);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapUp: widget.onSecondaryTap == null
              ? null
              : (d) => widget.onSecondaryTap!(d.globalPosition),
          onTertiaryTapUp: widget.onMiddleClick == null
              ? null
              : (_) => widget.onMiddleClick!(),
          child: Container(
            height: YsTab.height,
            color: bg,
            child: Stack(
              // A Stack lays its non-positioned children out top-start; the
              // tab content must sit on the vertical centre of the tab.
              alignment: AlignmentDirectional.centerStart,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(color: fg, size: 13),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.leading != null) widget.leading!,
                          if (widget.colorTag != null)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                color: widget.colorTag,
                                shape: BoxShape.circle,
                              ),
                            ),
                          widget.label,
                          for (final t in widget.trailing) t,
                          // Space is always reserved so hover never resizes the tab.
                          if (widget.onClose != null) ...[
                            const SizedBox(width: 4),
                            // Hidden != removed: the button stays in the focus
                            // order so Tab reaches it from the tab.
                            Opacity(
                              opacity: showClose ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !showClose,
                                child: ExcludeSemantics(
                                  excluding: !showClose,
                                  child: _CloseButton(
                                    onClose: widget.onClose!,
                                    tooltip: widget.closeTooltip,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (showRing)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: Key('ys-tab-focus-ring'),
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(color: YsColors.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (active)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2,
                    child: ColoredBox(
                      key: Key('ys-tab-indicator'),
                      color: YsColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onClose;
  final String? tooltip;
  const _CloseButton({required this.onClose, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: 20,
      height: 20,
      child: FButton.icon(
        variant: .ghost,
        size: .xs,
        onPress: onClose,
        child: const Icon(FLucideIcons.x, size: 12),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
