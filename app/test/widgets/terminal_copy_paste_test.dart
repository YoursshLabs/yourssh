// Regression tests for issue #43: copying from the terminal.
//
// Covers the keyboard copy/paste path of the xterm fork's TerminalView:
//   KeyDownEvent -> CustomTextEdit.onKeyEvent -> TerminalViewState._handleKeyEvent
//   -> ShortcutManager (defaultTerminalShortcuts) -> TerminalActions
//   -> Clipboard.setData / terminal.paste
//
// Windows/Linux expectations (issue #43):
//   - Ctrl+C with an active selection copies it (and clears the selection so
//     the next Ctrl+C reaches the shell as SIGINT).
//   - Ctrl+C without a selection falls through to the shell as ^C (0x03).
//   - Ctrl+Shift+C always copies (classic terminal binding).
//   - Ctrl+V and Ctrl+Shift+V paste.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
  });

  Future<void> pumpTerminal(
    WidgetTester tester,
    Terminal terminal,
    TerminalController controller,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'clipboard-content'};
        }
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Iterable<MethodCall> copyCalls() =>
      platformCalls.where((c) => c.method == 'Clipboard.setData');

  String? copiedText() => copyCalls().isEmpty
      ? null
      : (copyCalls().first.arguments as Map)['text'] as String?;

  void selectHello(Terminal terminal, TerminalController controller) {
    controller.setSelection(
      terminal.buffer.createAnchor(0, 0),
      terminal.buffer.createAnchor(5, 0),
    );
  }

  Future<void> pressCtrlC(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> pressCtrlV(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('macOS: Cmd+C copies the selection to the clipboard',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    selectHello(terminal, controller);
    await tester.pump();
    expect(controller.selection, isNotNull,
        reason: 'precondition: selection must exist before copying');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(copiedText(), 'hello');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows: Ctrl+Shift+C copies the selection to the clipboard',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    selectHello(terminal, controller);
    await tester.pump();

    await pressCtrlC(tester, shift: true);

    expect(copiedText(), 'hello');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'Windows: Ctrl+C with an active selection copies it, clears the '
      'selection and does not send SIGINT', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final terminal = Terminal();
    terminal.write('hello world');
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    selectHello(terminal, controller);
    await tester.pump();

    await pressCtrlC(tester);

    expect(copiedText(), 'hello',
        reason: 'Ctrl+C with selection should copy, not interrupt');
    expect(controller.selection, isNull,
        reason: 'selection should clear so the next Ctrl+C sends SIGINT');
    expect(output.join(), isNot(contains('\x03')),
        reason: 'no SIGINT should reach the shell while copying');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'Windows: Ctrl+C without selection sends SIGINT and does not touch '
      'the clipboard', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final terminal = Terminal();
    terminal.write('hello world');
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);
    expect(controller.selection, isNull);

    await pressCtrlC(tester);

    expect(copyCalls(), isEmpty,
        reason: 'no selection: Ctrl+C must not write to the clipboard');
    expect(output.join(), contains('\x03'),
        reason: 'Ctrl+C must keep working as SIGINT');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Linux: Ctrl+C with an active selection copies it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    selectHello(terminal, controller);
    await tester.pump();

    await pressCtrlC(tester);

    expect(copiedText(), 'hello');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows: Ctrl+Shift+V pastes the clipboard into the terminal',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final terminal = Terminal();
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    await pressCtrlV(tester, shift: true);

    expect(output.join(), contains('clipboard-content'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows: Ctrl+V pastes the clipboard into the terminal',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final terminal = Terminal();
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    await pressCtrlV(tester);

    expect(output.join(), contains('clipboard-content'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'Windows: double Ctrl+C while the clipboard write is in flight — '
      'second press sends SIGINT, not a second copy', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    // Clipboard whose setData hangs until released, so the second Ctrl+C
    // lands while the first copy is still awaiting the platform.
    final setDataReleased = Completer<void>();
    var setDataCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          setDataCalls++;
          await setDataReleased.future;
        }
        return null;
      },
    );

    final terminal = Terminal();
    terminal.write('hello world');
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pump();

    selectHello(terminal, controller);
    await tester.pump();

    await pressCtrlC(tester); // copy starts, setData hangs
    expect(setDataCalls, 1);
    expect(controller.selection, isNull,
        reason: 'selection must clear synchronously, not after setData');

    await pressCtrlC(tester); // must fall through to the shell as ^C
    expect(setDataCalls, 1, reason: 'second press must not copy again');
    expect(output.join(), contains('\x03'),
        reason: 'second press must interrupt (SIGINT)');

    setDataReleased.complete();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('middle-click pastes the clipboard into the terminal',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    final terminal = Terminal();
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await pumpTerminal(tester, terminal, controller);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TerminalView)),
      kind: PointerDeviceKind.mouse,
      buttons: kTertiaryButton,
    );
    await gesture.up();
    await tester.pump();

    expect(output.join(), contains('clipboard-content'));
    debugDefaultTargetPlatformOverride = null;
  });
}
