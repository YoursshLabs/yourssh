import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// App-styled confirmation dialog. Returns true only on explicit confirm.
/// [destructive] renders the confirm action in the destructive variant and
/// moves default focus to Cancel.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) => showYsConfirm(
  context,
  title: title,
  message: message,
  confirmLabel: confirmLabel,
  destructive: destructive,
);
