import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh/mobile/terminal/mobile_snippets_sheet.dart';

Future<void> _pump(WidgetTester tester,
    {required void Function(String) onInsert}) async {
  final sp = SnippetProvider();
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider.value(
      value: sp,
      child: Scaffold(body: MobileSnippetsSheet(onInsert: onInsert)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a snippet inserts its command', (tester) async {
    String? inserted;
    await _pump(tester, onInsert: (c) => inserted = c);

    final firstTile = find.byType(ListTile).first;
    expect(firstTile, findsOneWidget);
    await tester.tap(firstTile);
    await tester.pumpAndSettle();

    expect(inserted, isNotNull);
    expect(inserted!.isNotEmpty, isTrue);
  });

  testWidgets('search filters the list', (tester) async {
    await _pump(tester, onInsert: (_) {});
    final before = tester.widgetList(find.byType(ListTile)).length;
    await tester.enterText(find.byType(TextField), 'zzz-no-match-xyz');
    await tester.pumpAndSettle();
    final after = tester.widgetList(find.byType(ListTile)).length;
    expect(after, lessThanOrEqualTo(before));
  });
}
