/// YOURSSH PATCH (issue #43): the single source of truth for copy / paste /
/// select-all, shared by the keyboard intents (TerminalActions), the
/// middle-click paste gesture and the app's right-click context menu — so the
/// three input paths cannot drift apart.
library;

import 'package:flutter/services.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/selection_mode.dart';

/// Copies the active selection to the clipboard. No-op without a selection.
///
/// When [clearSelection] is true the selection is cleared *synchronously*,
/// before the clipboard write is awaited — Ctrl+C relies on this so a second
/// press reaches the shell as SIGINT even while (or if) the platform
/// clipboard call is slow or fails.
Future<void> terminalCopySelection(
  Terminal terminal,
  TerminalController controller, {
  bool clearSelection = false,
}) {
  final selection = controller.selection;
  if (selection == null) return Future.value();

  final text = terminal.buffer.getText(selection);
  if (clearSelection) {
    controller.clearSelection();
  }
  return Clipboard.setData(ClipboardData(text: text));
}

/// Reads plain text from the clipboard; null when empty/unavailable.
Future<String?> terminalClipboardText() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  return (text == null || text.isEmpty) ? null : text;
}

/// Sends [text] to the terminal as a paste and clears the selection.
void terminalPasteText(
  Terminal terminal,
  TerminalController controller,
  String text,
) {
  terminal.paste(text);
  controller.clearSelection();
}

/// Selects the whole visible buffer in line mode (same geometry for the
/// Ctrl/Cmd+A intent and the context menu).
void terminalSelectAll(Terminal terminal, TerminalController controller) {
  controller.setSelection(
    terminal.buffer.createAnchor(
      0,
      terminal.buffer.height - terminal.viewHeight,
    ),
    terminal.buffer.createAnchor(
      terminal.viewWidth,
      terminal.buffer.height - 1,
    ),
    mode: SelectionMode.line,
  );
}
