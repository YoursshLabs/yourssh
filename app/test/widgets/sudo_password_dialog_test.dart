import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/sudo_password_dialog.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh_ui/yourssh_ui.dart' show FCheckbox, FTextField, showYsDialog;

/// Holder so tests can observe the dialog result after it pops.
class _Result {
  ({String password, bool remember})? value;
  bool popped = false;
}

void main() {
  final host = Host(label: 'srv', host: '1.2.3.4', username: 'deploy');

  Future<_Result> pumpAndOpen(WidgetTester tester) async {
    final result = _Result();
    await tester.pumpWidget(MaterialApp(builder: ysRootBuilder,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result.value =
                await showYsDialog<({String password, bool remember})>(
            context,
            builder: (_) => SudoPasswordDialog(host: host),
            );
            result.popped = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(result.popped, isFalse); // dialog is showing
    return result;
  }

  testWidgets('submits password and remember flag', (tester) async {
    final result = await pumpAndOpen(tester);

    await tester.enterText(find.byType(EditableText), 's3cret');
    await tester.tap(find.byType(FCheckbox));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result.popped, isTrue);
    expect(result.value, (password: 's3cret', remember: true));
  });

  testWidgets('OK with empty password does not pop', (tester) async {
    final result = await pumpAndOpen(tester);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result.popped, isFalse);
    expect(find.byType(SudoPasswordDialog), findsOneWidget);
  });

  testWidgets('field is focused, obscured and Enter submits', (tester) async {
    final result = await pumpAndOpen(tester);

    expect(find.byType(FTextField), findsOneWidget);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.obscureText, isTrue);
    expect(editable.focusNode.hasFocus, isTrue);
    expect(find.text('Remember in system keychain'), findsOneWidget);
    expect(find.textContaining('needs the sudo password.'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'pw');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result.value, (password: 'pw', remember: false));
  });

  testWidgets('Escape (safe path) returns null', (tester) async {
    final result = await pumpAndOpen(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result.popped, isTrue);
    expect(result.value, isNull);
  });

  testWidgets('cancel returns null', (tester) async {
    final result = await pumpAndOpen(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result.popped, isTrue);
    expect(result.value, isNull);
    expect(find.byType(SudoPasswordDialog), findsNothing);
  });
}
