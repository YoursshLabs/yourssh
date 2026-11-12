import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// Shows a modal dialog through forui's dialog route (blurred, token-tinted
/// barrier, forui transition).
///
/// Always pushes on the root navigator, like `showDialog`, so the dialog
/// covers nested navigators and inherits the root `FTheme`. Escape and a
/// barrier tap close it only while [barrierDismissible] is true; the future
/// then completes with `null`.
///
/// The barrier closes the route with `Navigator.pop`, not `maybePop`, so a
/// `PopScope` inside the dialog is bypassed: a dialog guarding against
/// dismissal must pass `barrierDismissible: false`.
Future<T?> showYsDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showFDialog<T>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: barrierDismissible,
  builder: (ctx, style, animation) => builder(ctx),
);

/// A forui dialog with a title, optional body and a row of [actions]
/// (right-aligned, wrapping when narrow).
///
/// Build the buttons with `FButton` (`FButtonVariant.primary` for the
/// affirmative action, `outline`/`ghost` for cancel, `destructive` for
/// irreversible ones). Give the safe choice `autofocus: true`.
class YsDialog extends StatelessWidget {
  const YsDialog({
    super.key,
    this.title,
    this.titleWidget,
    this.body,
    this.actions = const [],
    this.maxWidth = 560,
    this.semanticsLabel,
  }) : assert(
         (title == null) != (titleWidget == null),
         'Provide exactly one of title or titleWidget',
       );

  /// Plain-text title.
  final String? title;

  /// Rich title (icon + text rows) for dialogs that need more than a string.
  final Widget? titleWidget;

  /// Dialog content. Laid out like `AlertDialog.content`: flexible, so a tall
  /// body should scroll itself.
  final Widget? body;

  final List<Widget> actions;

  final double maxWidth;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    return FDialog(
      animation: animation,
      semanticsLabel: semanticsLabel ?? title,
      constraints: BoxConstraints(minWidth: 280, maxWidth: maxWidth),
      builder: (ctx, style) => Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(YsSpace.s5),
          // Size to content (up to maxWidth), like AlertDialog.
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DefaultTextStyle.merge(
                  style: style.titleTextStyle,
                  child: titleWidget ?? Text(title!),
                ),
                if (body != null) ...[
                  const SizedBox(height: YsSpace.s3),
                  Flexible(
                    child: DefaultTextStyle.merge(
                      style: style.bodyTextStyle,
                      child: body!,
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: YsSpace.s5),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: YsSpace.s2,
                      runSpacing: YsSpace.s2,
                      // FButton fills the width by default; give each action
                      // its intrinsic width so the row is content-sized and
                      // only wraps when the buttons really do not fit.
                      children: [
                        for (final a in actions) IntrinsicWidth(child: a),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a confirm dialog and returns whether the user confirmed.
///
/// Returns `false` on cancel, barrier tap or Escape. When [destructive], the
/// confirm button uses the destructive variant and **Cancel** holds default
/// focus (so a stray Enter never destroys anything); otherwise confirm holds
/// focus and Enter confirms.
Future<bool> showYsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final ok = await showYsDialog<bool>(
    context,
    builder: (ctx) => YsDialog(
      title: title,
      body: Text(message),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          autofocus: destructive,
          onPress: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FButton(
          variant: destructive
              ? FButtonVariant.destructive
              : FButtonVariant.primary,
          autofocus: !destructive,
          onPress: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Card shell for dialogs that lay out their own content (editors, pickers,
/// multi-section forms): card background, 10 px radius, border, 24 px padding.
/// Use inside [showYsDialog]; replaces `Dialog(backgroundColor: ...)`.
///
/// Pass `padding: EdgeInsets.zero` for edge-to-edge layouts (header bars,
/// full-bleed panes); content is clipped to the rounded card either way.
class YsDialogFrame extends StatelessWidget {
  const YsDialogFrame({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.padding = const EdgeInsets.all(YsSpace.s5),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    Widget frame = Align(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 80),
        child: Padding(
          padding: EdgeInsets.fromLTRB(40, 24, 40, 24 + keyboard),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: YsColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YsRadius.card),
                side: const BorderSide(color: YsColors.border),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(YsRadius.card),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null) {
      frame = FadeTransition(opacity: animation, child: frame);
    }
    return frame;
  }
}
