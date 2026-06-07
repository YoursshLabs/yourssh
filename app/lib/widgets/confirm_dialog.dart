import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// App-styled confirmation dialog. Returns true only on explicit confirm.
/// [destructive] renders the confirm action in red.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: Text(message,
          style:
              const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: destructive ? const TextStyle(color: Colors.red) : null)),
      ],
    ),
  );
  return ok == true;
}
