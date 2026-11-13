import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/rdp_password_dialog.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(WidgetTester tester, List<String?> results) async {
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (ctx) => FButton(
            onPress: () async => results.add(
              await showYsDialog<String>(
                ctx,
                builder: (_) => RdpPasswordDialog(
                  host: Host(
                    id: 'h',
                    label: 'rdp-box',
                    host: '1.2.3.4',
                    username: 'u',
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows title, focused password field and actions',
      (tester) async {
    await open(tester, []);
    expect(find.text('Password for rdp-box'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.byKey(const Key('rdp-password')), findsOneWidget);
  });

  testWidgets('Enter submits the typed password', (tester) async {
    final results = <String?>[];
    await open(tester, results);
    await tester.enterText(find.byType(EditableText), 's3cret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(results, ['s3cret']);
  });

  testWidgets('Cancel returns null', (tester) async {
    final results = <String?>[];
    await open(tester, results);
    await tester.enterText(find.byType(EditableText), 'x');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('Escape returns null', (tester) async {
    final results = <String?>[];
    await open(tester, results);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
