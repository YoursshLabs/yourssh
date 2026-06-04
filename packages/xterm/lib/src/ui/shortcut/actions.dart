import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/selection_mode.dart';
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
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final text = data?.text;
            if (text != null) {
              terminal.paste(text);
              controller.clearSelection();
            }
            return null;
          },
        ),
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) async {
            final selection = controller.selection;

            if (selection == null) {
              return;
            }

            final text = terminal.buffer.getText(selection);

            await Clipboard.setData(ClipboardData(text: text));

            return null;
          },
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
  Object? invoke(TerminalCopyAndClearIntent intent) async {
    final selection = controller.selection;

    if (selection == null) {
      return null;
    }

    final text = terminal.buffer.getText(selection);

    await Clipboard.setData(ClipboardData(text: text));

    controller.clearSelection();

    return null;
  }
}
