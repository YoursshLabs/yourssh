// app/test/widgets/permissions_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/permissions_dialog.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh_ui/yourssh_ui.dart'
    show FButton, FCheckbox, FTextField, showYsDialog;

Future<({int mode, bool recursive})?> _open(
  WidgetTester tester, {
  required int? initialMode,
  bool isDirectory = false,
}) async {
  ({int mode, bool recursive})? result;
  await tester.pumpWidget(
    MaterialApp(
      builder: ysRootBuilder,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showYsDialog<({int mode, bool recursive})>(
              context,
              builder: (_) => PermissionsDialog(
                entryName: 'notes.txt',
                initialMode: initialMode,
                isDirectory: isDirectory,
              ),
            );
          },
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

Finder _octal(String text) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == text,
);

FTextField _octalField(WidgetTester tester) =>
    tester.widget<FTextField>(find.byType(FTextField));

void main() {
  testWidgets('invalid octal puts the field in its error state; valid clears', (
    tester,
  ) async {
    await _open(tester, initialMode: 0x1A4);
    expect(_octalField(tester).error, isNull);

    await tester.enterText(find.byType(EditableText), '64');
    await tester.pump();
    expect(_octalField(tester).error, isNotNull);

    await tester.enterText(find.byType(EditableText), '640');
    await tester.pump();
    expect(_octalField(tester).error, isNull);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('preloads octal field and checkboxes from initialMode', (
    tester,
  ) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    expect(_octal('644'), findsOneWidget);
    final ownerWrite = tester.widget<FCheckbox>(
      find.byKey(const Key('perm_u_w')),
    );
    final otherWrite = tester.widget<FCheckbox>(
      find.byKey(const Key('perm_o_w')),
    );
    expect(ownerWrite.value, isTrue);
    expect(otherWrite.value, isFalse);
  });

  testWidgets('toggling a checkbox updates the octal field', (tester) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    await tester.tap(find.byKey(const Key('perm_u_x')));
    await tester.pumpAndSettle();
    expect(_octal('744'), findsOneWidget);
  });

  testWidgets('editing the octal field updates the checkboxes', (tester) async {
    await _open(tester, initialMode: 0x1A4);
    await tester.enterText(find.byType(EditableText), '777');
    await tester.pumpAndSettle();
    final otherWrite = tester.widget<FCheckbox>(
      find.byKey(const Key('perm_o_w')),
    );
    expect(otherWrite.value, isTrue);
  });

  testWidgets('Apply returns the edited mode', (tester) async {
    ({int mode, bool recursive})? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: ysRootBuilder,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showYsDialog<({int mode, bool recursive})>(
                context,
                builder: (_) => const PermissionsDialog(
                  entryName: 'notes.txt',
                  initialMode: 0x1A4,
                  isDirectory: false,
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '755');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, (mode: 0x1ED, recursive: false));
  });

  FButton applyButton(WidgetTester tester) => tester.widget<FButton>(
    find.ancestor(of: find.text('Apply'), matching: find.byType(FButton)),
  );

  testWidgets('Apply is disabled while the octal text is incomplete', (
    tester,
  ) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    await tester.enterText(find.byType(EditableText), '64'); // half-typed
    await tester.pump();
    expect(applyButton(tester).onPress, isNull);
    expect(find.text('3–4 octal digits'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '640');
    await tester.pump();
    expect(applyButton(tester).onPress, isNotNull);
  });

  testWidgets('non-octal characters are filtered out of the field', (
    tester,
  ) async {
    await _open(tester, initialMode: 0x1A4);
    await tester.enterText(find.byType(EditableText), '9a8b');
    await tester.pump();
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, isEmpty); // everything non-octal dropped
    expect(applyButton(tester).onPress, isNull);
  });

  testWidgets('unknown initialMode shows a warning and gates Apply', (
    tester,
  ) async {
    await _open(tester, initialMode: null);
    expect(
      find.text('Current permissions unknown — set them before applying.'),
      findsOneWidget,
    );
    expect(applyButton(tester).onPress, isNull);

    await tester.tap(find.byKey(const Key('perm_u_r')));
    await tester.pump();
    expect(_octal('400'), findsOneWidget);
    expect(applyButton(tester).onPress, isNotNull);
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // drain FTappable press timers
  });

  testWidgets('recursive checkbox only shown for directories', (tester) async {
    await _open(tester, initialMode: 0x1ED, isDirectory: false);
    expect(find.text('Apply recursively'), findsNothing);
    // Dismiss and reopen as directory.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await _open(tester, initialMode: 0x1ED, isDirectory: true);
    expect(find.text('Apply recursively'), findsOneWidget);
  });
}
