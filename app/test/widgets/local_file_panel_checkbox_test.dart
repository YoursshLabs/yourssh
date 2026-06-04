// Local panel checkbox selection — parity with the remote SFTP panel
// (per-row checkboxes + select-all header with a selection count).
//
// LocalFilePanel schedules a real-filesystem reload on mount; the harness
// overrides the provider state with setEntriesForTest after that kicks off
// (the real fetch never completes inside the fake-async test zone), keeping
// the rendered list deterministic.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/local_entry.dart';
import 'package:yourssh/providers/local_file_panel_provider.dart';
import 'package:yourssh/widgets/local_file_panel.dart';

LocalEntry _entry(String name) => LocalEntry(
      name: name,
      path: '/files/$name',
      isDirectory: false,
      size: 10,
      modifiedAt: DateTime(2026),
      permissions: '-rw-r--r--',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalFilePanelProvider provider;

  setUp(() {
    provider = LocalFilePanelProvider.forTest('/files');
  });

  tearDown(() => provider.dispose());

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalFilePanel(provider: provider, onChangeSource: () {}),
        ),
      ),
    );
    await tester.pump(); // mount reload kicks off (never lands in fake zone)
    provider.setEntriesForTest([_entry('a.txt'), _entry('b.txt')]);
    await tester.pump();
  }

  testWidgets('renders a checkbox per row plus a select-all header',
      (tester) async {
    await pumpPanel(tester);
    expect(find.byType(Checkbox), findsNWidgets(3),
        reason: '2 rows + 1 select-all header');
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('select-all header selects all visible entries', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.byKey(const Key('local_select_all')));
    await tester.pump();
    expect(provider.selectedEntries.length, 2);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('local_select_all')));
    await tester.pump();
    expect(provider.selectedEntries, isEmpty);
  });

  testWidgets('row checkbox toggles that entry', (tester) async {
    await pumpPanel(tester);

    // Index 0 is the header; rows follow in list order.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(provider.selectedEntries.map((e) => e.name), ['a.txt']);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(provider.selectedEntries, isEmpty);
  });
}
