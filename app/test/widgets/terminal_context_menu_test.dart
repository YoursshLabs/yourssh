// Right-click context menu for terminal views (issue #43): users expect a
// Copy/Paste menu on secondary click, working on every desktop platform.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/widgets/terminal_context_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
  });

  Future<void> pumpHarness(
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
          body: Builder(
            builder: (context) => TerminalView(
              terminal,
              controller: controller,
              autofocus: true,
              onSecondaryTapUp: (details, offset) => showTerminalContextMenu(
                context: context,
                globalPosition: details.globalPosition,
                terminal: terminal,
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> rightClickTerminal(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TerminalView)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Iterable<MethodCall> copyCalls() =>
      platformCalls.where((c) => c.method == 'Clipboard.setData');

  testWidgets('right-click opens a menu with Copy, Paste and Select All',
      (tester) async {
    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpHarness(tester, terminal, controller);
    await rightClickTerminal(tester);

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
  });

  testWidgets('menu Copy puts the selection on the clipboard', (tester) async {
    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpHarness(tester, terminal, controller);

    controller.setSelection(
      terminal.buffer.createAnchor(0, 0),
      terminal.buffer.createAnchor(5, 0),
    );
    await tester.pump();

    await rightClickTerminal(tester);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copyCalls(), isNotEmpty);
    expect((copyCalls().first.arguments as Map)['text'], 'hello');
  });

  testWidgets('menu Copy is disabled when there is no selection',
      (tester) async {
    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpHarness(tester, terminal, controller);
    expect(controller.selection, isNull);

    await rightClickTerminal(tester);

    final copyItem = tester.widget<PopupMenuItem<TerminalMenuAction>>(
      find.ancestor(
        of: find.text('Copy'),
        matching: find.byWidgetPredicate(
            (w) => w is PopupMenuItem<TerminalMenuAction>),
      ),
    );
    expect(copyItem.enabled, isFalse);
  });

  testWidgets('menu Paste sends the clipboard to the terminal',
      (tester) async {
    final terminal = Terminal();
    final output = <String>[];
    terminal.onOutput = output.add;
    final controller = TerminalController();

    await pumpHarness(tester, terminal, controller);

    await rightClickTerminal(tester);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(output.join(), contains('clipboard-content'));
  });

  testWidgets('menu Select All selects the whole buffer', (tester) async {
    final terminal = Terminal();
    terminal.write('hello world');
    final controller = TerminalController();

    await pumpHarness(tester, terminal, controller);
    expect(controller.selection, isNull);

    await rightClickTerminal(tester);
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();

    expect(controller.selection, isNotNull);
  });
}
