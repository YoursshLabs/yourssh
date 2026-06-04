import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Actions offered by the terminal right-click menu (issue #43).
enum TerminalMenuAction { copy, paste, selectAll }

/// Shows the Copy / Paste / Select All context menu for a terminal at
/// [globalPosition] and performs the chosen action.
///
/// Shared by the SSH terminal and the local terminal panes.
Future<void> showTerminalContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Terminal terminal,
  required TerminalController controller,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;

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
    ],
  );

  switch (action) {
    case TerminalMenuAction.copy:
      final selection = controller.selection;
      if (selection != null) {
        await Clipboard.setData(
            ClipboardData(text: terminal.buffer.getText(selection)));
      }
    case TerminalMenuAction.paste:
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        terminal.paste(text);
        controller.clearSelection();
      }
    case TerminalMenuAction.selectAll:
      controller.setSelection(
        terminal.buffer.createAnchor(
          0,
          terminal.buffer.height - terminal.viewHeight,
        ),
        terminal.buffer.createAnchor(
          terminal.viewWidth,
          terminal.buffer.height - 1,
        ),
      );
    case null:
      break;
  }
}
