import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Actions offered by the terminal right-click menu (issue #43).
enum TerminalMenuAction { copy, paste, selectAll, resetTerminal }

/// Shows the Copy / Paste / Select All context menu for a terminal at
/// [globalPosition] and performs the chosen action.
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
    items: [
      PopupMenuItem(
        value: TerminalMenuAction.copy,
        enabled: controller.selection != null,
        height: 36,
        child: const Text('Copy'),
      ),
      PopupMenuItem(
        value: TerminalMenuAction.paste,
        height: 36,
        child: const Text('Paste'),
      ),
      PopupMenuItem(
        value: TerminalMenuAction.selectAll,
        height: 36,
        child: const Text('Select All'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: TerminalMenuAction.resetTerminal,
        height: 36,
        child: const Text('Reset Terminal'),
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
