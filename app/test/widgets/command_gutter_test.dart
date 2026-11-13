import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/widgets/command_gutter.dart';

void main() {
  late ShellIntegrationProvider shell;
  late ScrollController scroll;

  setUp(() {
    shell = ShellIntegrationProvider();
    scroll = ScrollController();
  });

  tearDown(() {
    shell.dispose();
    scroll.dispose();
  });

  Widget harness({void Function(int)? onJumpTo}) =>
      ChangeNotifierProvider<ShellIntegrationProvider>.value(
        value: shell,
        child: MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 400,
              child: CommandGutter(
                sessionId: 's1',
                scrollController: scroll,
                lineHeight: 20,
                onJumpTo: onJumpTo,
              ),
            ),
          ),
        ),
      );

  Finder dots() => find.descendant(
    of: find.byType(CommandGutter),
    matching: find.byType(CustomPaint),
  );

  testWidgets('empty until the session has commands', (tester) async {
    await tester.pumpWidget(harness());
    expect(dots(), findsNothing);

    shell.handleOsc('s1', '133', ['A'], 3);
    await tester.pump();
    expect(dots(), findsOneWidget);
  });

  testWidgets('tapping next to a prompt dot jumps to its line', (tester) async {
    int? jumped;
    shell.handleOsc('s1', '133', ['A'], 5);
    await tester.pumpWidget(harness(onJumpTo: (l) => jumped = l));

    // Line 5 is centred at 5 * 20 + 10 = 110 px.
    await tester.tapAt(const Offset(4, 110));
    expect(jumped, 5);

    jumped = null;
    await tester.tapAt(const Offset(4, 300)); // far from any dot
    expect(jumped, isNull);
  });

  testWidgets('ignores other sessions\' commands', (tester) async {
    await tester.pumpWidget(harness());
    shell.handleOsc('other', '133', ['A'], 1);
    await tester.pump();
    expect(dots(), findsNothing);
  });
}
