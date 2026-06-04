import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Map<ShortcutActivator, Intent> get defaultTerminalShortcuts {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return _defaultShortcuts;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _defaultAppleShortcuts;
  }
}

/// YOURSSH PATCH (issue #43): copy/paste on Windows/Linux was effectively
/// unreachable for most users — Ctrl+C always meant SIGINT and the only copy
/// binding was Ctrl+Shift+C. Mirror Windows Terminal behavior instead:
/// Ctrl+C copies when a selection is active (the action is disabled
/// otherwise, so the key falls through to the shell as ^C), and
/// Ctrl+Shift+V is accepted as a paste alias alongside Ctrl+V.
class TerminalCopyAndClearIntent extends Intent {
  const TerminalCopyAndClearIntent();
}

final _defaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyC, control: true):
      const TerminalCopyAndClearIntent(),
  SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, control: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};

final _defaultAppleShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};
