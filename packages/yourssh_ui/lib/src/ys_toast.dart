import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';

/// Visual kind of a toast shown by [showYsToast].
enum YsToastKind { info, success, error }

/// Shows a toast on the nearest [FToaster] above [context].
///
/// info/success auto-dismiss after 3 s, error after 5 s unless [duration] is
/// given. When [actionLabel] and [onAction] are both set, a button is shown;
/// pressing it runs [onAction] and dismisses the toast. Toasts are placed at
/// the bottom-right on desktop and bottom-centre on touch platforms.
void showYsToast(
  BuildContext context,
  String message, {
  YsToastKind kind = YsToastKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final isError = kind == YsToastKind.error;
  final touch = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  showFToast(
    context: context,
    variant: isError ? FToastVariant.destructive : FToastVariant.primary,
    alignment: touch ? FToastAlignment.bottomCenter : FToastAlignment.bottomRight,
    duration: duration ??
        (isError ? const Duration(seconds: 5) : const Duration(seconds: 3)),
    icon: switch (kind) {
      YsToastKind.error => const Icon(FLucideIcons.circleAlert),
      YsToastKind.success =>
        const Icon(FLucideIcons.circleCheck, color: YsColors.ok),
      YsToastKind.info => null,
    },
    title: Text(message),
    suffixBuilder: actionLabel != null && onAction != null
        ? (context, entry) => FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.xs,
              mainAxisSize: MainAxisSize.min,
              onPress: () {
                entry.dismiss();
                onAction();
              },
              child: Text(actionLabel),
            )
        : null,
  );
}
