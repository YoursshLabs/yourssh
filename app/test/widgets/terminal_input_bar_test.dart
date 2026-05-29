import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/widgets/suggestion_popup.dart';
import 'package:yourssh/widgets/terminal_input_bar.dart';

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
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<CommandHistoryProvider>.value(
          value: historyProvider,
          child: TerminalInputBar(
            sessionId: 's1',
            onSubmit: onSubmit,
            onDismiss: onDismiss ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('suggestions appear after typing a prefix', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    await tester.enterText(find.byType(TextField), 'git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);
    expect(find.text('git status'), findsOneWidget);
  });

  testWidgets('Tab completes first suggestion into text field without submitting', (tester) async {
    String? submitted;
    await tester.pumpWidget(wrap(onSubmit: (cmd) => submitted = cmd));
    await tester.enterText(find.byType(TextField), 'git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(submitted, isNull);
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text.startsWith('git'), isTrue);
    expect(tf.controller!.text.length, greaterThan(3));
  });

  testWidgets('Tab with no suggestions does not submit', (tester) async {
    String? submitted;
    await tester.pumpWidget(wrap(onSubmit: (cmd) => submitted = cmd));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(submitted, isNull);
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text, 'zzz');
  });

  testWidgets('ArrowDown moves selection highlight when suggestions visible', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    await tester.enterText(find.byType(TextField), 'git');
    await tester.pump();
    expect(find.byType(SuggestionPopup), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final highlighted = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == const Color(0xFF1E3A5F);
    });
    expect(highlighted.length, greaterThanOrEqualTo(1));
  });

  testWidgets('ArrowUp navigates history when no suggestions', (tester) async {
    await tester.pumpWidget(wrap(onSubmit: (_) {}));
    // No text — no suggestions
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text, isNotEmpty);
  });
}
