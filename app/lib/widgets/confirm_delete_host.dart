import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/host.dart';

/// Asks before a saved host (and its stored passwords) is removed. Shared by
/// the host editor and the dashboard card menu. Cancel holds default focus.
Future<bool> confirmDeleteHost(BuildContext context, Host host) {
  final name = host.label.isEmpty ? host.host : host.label;
  return showYsConfirm(
    context,
    title: 'Delete host?',
    message: '"$name" and its saved password will be removed.',
    confirmLabel: 'Delete',
    destructive: true,
  );
}
