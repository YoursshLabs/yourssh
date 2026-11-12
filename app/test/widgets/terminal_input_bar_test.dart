import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/widgets/suggestion_popup.dart';
import 'package:yourssh/widgets/terminal_input_bar.dart';

import '../helpers/ys_test_app.dart';

void main() {
  late CommandHistoryProvider historyProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    historyProvider = CommandHistoryProvider();
    historyProvider.recordCommand('s1', 'git diff');
    historyProvider.recordCommand('s1', 'git log');
    historyProvider.recordCommand('s1', 'git status');
    await Future.delayed(Duration.zero); // let async persist settle
  });

  Widget wrap({required void Function(String) onSubmit, VoidCallback? onDismiss}) {
    return ChangeNotifierProvider<CommandHistoryProvider>.value(
      value: historyProvider,
      child: ysTestApp(
        TerminalInputBar(
          sessionId: 's1',
          onSubmit: onSubmit,
          onDismiss: onDismiss ?? () {},
        ),
      ),
    );
  }

  // The forui field wraps material_ui's TextField, so find it by key and read
  // the text from its EditableText.
  final inputField = find.byKey(const Key('terminal-input-field'));
  String inputText(WidgetTester tester) => tester
      .widget<EditableText>(
          find.descendant(of: inputField, matching: find.byType(EditableText)))
      .controller
      .text;

  testWidgets('suggestions appear after typing a prefix', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    await tester.enterText(inputField, 'git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
  });

  testWidgets('Tab completes first suggestion into text field without submitting', (tester) async {
    String? submitted;
    await tester.pumpWidget(wrap(onSubmit: (cmd) => submitted = cmd));
    await tester.enterText(inputField, 'git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(submitted, isNull);
    expect(inputText(tester).startsWith('git'), isTrue);
    expect(inputText(tester).length, greaterThan(3));
  });

  testWidgets('Tab with no suggestions does not submit', (tester) async {
    String? submitted;
    await tester.pumpWidget(wrap(onSubmit: (cmd) => submitted = cmd));
    await tester.enterText(inputField, 'zzz');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(submitted, isNull);
    expect(inputText(tester), 'zzz');
  });

  testWidgets('ArrowDown moves selection highlight when suggestions visible', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    await tester.enterText(inputField, 'git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final highlighted = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == kSuggestionSelectedColor;
    });
    expect(highlighted.length, greaterThanOrEqualTo(1));
  });

  testWidgets('ArrowUp navigates history when no suggestions', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    // No text — no suggestions
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(inputText(tester), isNotEmpty);
  });

  testWidgets(
      'keyboard flow: typing right after opening lands in the field, '
      'Escape then dismisses', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
        wrap(onSubmit: (_) {}, onDismiss: () => dismissed++));
    await tester.pump();

    // No tap: the field itself must hold focus with an open text-input
    // connection, or keystrokes are lost until the user clicks it.
    expect(tester.testTextInput.hasAnyClients, isTrue,
        reason: 'the field is the text-input client on open');
    tester.testTextInput.enterText('uptime');
    await tester.pump();
    expect(inputText(tester), 'uptime');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(dismissed, 1);
  });

  testWidgets(
      'keyboard flow: Enter submits and clears, and the field keeps taking '
      'typing for the next command', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(wrap(onSubmit: submitted.add));
    await tester.pump();

    tester.testTextInput.enterText('uptime');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, ['uptime\n']);
    expect(inputText(tester), isEmpty);

    tester.testTextInput.enterText('df -h');
    await tester.pump();
    expect(inputText(tester), 'df -h');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, ['uptime\n', 'df -h\n']);
    await tester.pump(const Duration(seconds: 1)); // history persist debounce
  });

  testWidgets('keyboard flow: Tab and arrows still reach the bar from the '
      'focused field', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    await tester.pump();

    tester.testTextInput.enterText('git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(inputText(tester).startsWith('git'), isTrue);
    expect(inputText(tester).length, greaterThan(3));
  });
}
