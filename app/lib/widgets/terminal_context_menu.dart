import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'ys_menu.dart';

/// Actions offered by the terminal right-click menu (issue #43).
enum TerminalMenuAction { copy, paste, selectAll, resetTerminal }

/// Shows the Copy / Paste / Select All / Reset Terminal context menu for a
/// terminal at [globalPosition] (token-styled `showMenu`, see `ys_menu.dart`)
/// and performs the chosen action.
///
/// Shared by the SSH terminal and the local terminal panes. The actual
/// clipboard/selection work delegates to the xterm fork's clipboard ops so
/// the menu can never drift from the keyboard shortcuts and middle-click.
Future<void> showTerminalContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Terminal terminal,
  required TerminalController controller,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  final action = await showMenu<TerminalMenuAction>(
    context: context,
    position: RelativeRect.fromSize(
      globalPosition & Size.zero,
      overlay.size,
    ),
    color: kYsMenuColor,
    shape: kYsMenuShape,
    items: [
      ysMenuItem(
        TerminalMenuAction.copy,
        FLucideIcons.copy,
        'Copy',
        enabled: controller.selection != null,
        height: 36,
      ),
      ysMenuItem(
        TerminalMenuAction.paste,
        FLucideIcons.clipboardPaste,
        'Paste',
        height: 36,
      ),
      ysMenuItem(
        TerminalMenuAction.selectAll,
        FLucideIcons.textSelect,
        'Select All',
        height: 36,
      ),
      const PopupMenuDivider(height: 9),
      ysMenuItem(
        TerminalMenuAction.resetTerminal,
        FLucideIcons.rotateCcw,
        'Reset Terminal',
        height: 36,
      ),
    ],
  );

  // The menu (and the clipboard fetch below) are async — the pane that
  // spawned us may have been disposed in the meantime (session drop, hotkey
  // close). Its controller dies with it, so bail out.
  if (!context.mounted) return;

  switch (action) {
    case TerminalMenuAction.copy:
      await terminalCopySelection(terminal, controller);
    case TerminalMenuAction.paste:
      final text = await terminalClipboardText();
      if (!context.mounted) return;
      if (text != null) {
        terminalPasteText(terminal, controller, text);
      }
    case TerminalMenuAction.selectAll:
      terminalSelectAll(terminal, controller);
    case TerminalMenuAction.resetTerminal:
      // A full-screen app that died uncleanly can leave the terminal stuck
      // in the alternate screen with mouse reporting on — wheel scrolling
      // goes dead until recovered (the `reset` command equivalent).
      terminal.recoverFromStuckState();
    case null:
      break;
  }
}
