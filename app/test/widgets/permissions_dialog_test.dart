// app/test/widgets/permissions_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/permissions_dialog.dart';

Future<({int mode, bool recursive})?> _open(
  WidgetTester tester, {
  required int? initialMode,
  bool isDirectory = false,
}) async {
  ({int mode, bool recursive})? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await showDialog<({int mode, bool recursive})>(
            context: context,
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
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('preloads octal field and checkboxes from initialMode',
      (tester) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    expect(find.widgetWithText(TextField, '644'), findsOneWidget);
    final ownerWrite =
        tester.widget<Checkbox>(find.byKey(const Key('perm_u_w')));
    final otherWrite =
        tester.widget<Checkbox>(find.byKey(const Key('perm_o_w')));
    expect(ownerWrite.value, isTrue);
    expect(otherWrite.value, isFalse);
  });

  testWidgets('toggling a checkbox updates the octal field', (tester) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    await tester.tap(find.byKey(const Key('perm_u_x')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '744'), findsOneWidget);
  });

  testWidgets('editing the octal field updates the checkboxes',
      (tester) async {
    await _open(tester, initialMode: 0x1A4);
    await tester.enterText(find.byType(TextField), '777');
    await tester.pumpAndSettle();
    final otherWrite =
        tester.widget<Checkbox>(find.byKey(const Key('perm_o_w')));
    expect(otherWrite.value, isTrue);
  });

  testWidgets('Apply returns the edited mode', (tester) async {
    ({int mode, bool recursive})? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<({int mode, bool recursive})>(
              context: context,
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
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '755');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, (mode: 0x1ED, recursive: false));
  });

  TextButton applyButton(WidgetTester tester) => tester.widget<TextButton>(
        find.ancestor(
            of: find.text('Apply'), matching: find.byType(TextButton)),
      );

  testWidgets('Apply is disabled while the octal text is incomplete',
      (tester) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    await tester.enterText(find.byType(TextField), '64'); // half-typed
    await tester.pump();
    expect(applyButton(tester).onPressed, isNull);
    expect(find.text('3–4 octal digits'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '640');
    await tester.pump();
    expect(applyButton(tester).onPressed, isNotNull);
  });

  testWidgets('non-octal characters are filtered out of the field',
      (tester) async {
    await _open(tester, initialMode: 0x1A4);
    await tester.enterText(find.byType(TextField), '9a8b');
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty); // everything non-octal dropped
    expect(applyButton(tester).onPressed, isNull);
  });

  testWidgets('unknown initialMode shows a warning and gates Apply',
      (tester) async {
    await _open(tester, initialMode: null);
    expect(
        find.text('Current permissions unknown — set them before applying.'),
        findsOneWidget);
    expect(applyButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('perm_u_r')));
    await tester.pump();
    expect(find.widgetWithText(TextField, '400'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNotNull);
  });

  testWidgets('recursive checkbox only shown for directories',
      (tester) async {
    await _open(tester, initialMode: 0x1ED, isDirectory: false);
    expect(find.text('Apply recursively'), findsNothing);
    // Dismiss and reopen as directory.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await _open(tester, initialMode: 0x1ED, isDirectory: true);
    expect(find.text('Apply recursively'), findsOneWidget);
  });
}
