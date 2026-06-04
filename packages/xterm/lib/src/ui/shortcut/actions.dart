import 'package:flutter/widgets.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/clipboard_ops.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/shortcut/shortcuts.dart';

class TerminalActions extends StatelessWidget {
  const TerminalActions({
    super.key,
    required this.terminal,
    required this.controller,
    required this.child,
  });

  final Terminal terminal;

  final TerminalController controller;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (intent) async {
            final text = await terminalClipboardText();
            if (text != null) {
              terminalPasteText(terminal, controller, text);
            }
            return null;
          },
        ),
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) =>
              terminalCopySelection(terminal, controller),
        ),
        // YOURSSH PATCH (issue #43): Ctrl+C copies when a selection is
        // active. The action reports disabled without a selection, so
        // ShortcutManager ignores the key and it reaches the shell as ^C.
        TerminalCopyAndClearIntent: _CopySelectionAndClearAction(
          terminal: terminal,
          controller: controller,
        ),
        SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
          onInvoke: (intent) {
            terminalSelectAll(terminal, controller);
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

/// Copies the active selection to the clipboard, then clears it so the next
/// Ctrl+C reaches the shell as SIGINT. Disabled when there is no selection,
/// which makes [ShortcutManager.handleKeypress] ignore the key entirely.
///
/// The selection is cleared synchronously inside [terminalCopySelection] —
/// before the platform clipboard write is awaited — so a rapid second Ctrl+C
/// always interrupts instead of copying again, and a failing clipboard
/// backend cannot leave the selection stuck.
class _CopySelectionAndClearAction extends Action<TerminalCopyAndClearIntent> {
  _CopySelectionAndClearAction({
    required this.terminal,
    required this.controller,
  });

  final Terminal terminal;

  final TerminalController controller;

  @override
  bool isEnabled(TerminalCopyAndClearIntent intent, [BuildContext? context]) {
    return controller.selection != null;
  }

  @override
  Object? invoke(TerminalCopyAndClearIntent intent) {
    return terminalCopySelection(terminal, controller, clearSelection: true);
  }
}
