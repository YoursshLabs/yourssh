import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/command_palette.dart';

void main() {
  group('CommandPaletteSearcher.score', () {
    test('returns 0 when query is not a subsequence of target', () {
      expect(CommandPaletteSearcher.score('xyz', 'prod-db'), 0);
    });

    test('returns positive score for valid subsequence', () {
      expect(CommandPaletteSearcher.score('pd', 'prod-db'), greaterThan(0));
    });

    test('scores "pd" against "prod-db" higher than against "padding"', () {
      final scoreProdb = CommandPaletteSearcher.score('pd', 'prod-db');
      final scorePadding = CommandPaletteSearcher.score('pd', 'padding');
      expect(scoreProdb, greaterThan(scorePadding));
    });

    test('returns positive score for empty query', () {
      expect(CommandPaletteSearcher.score('', 'anything'), greaterThan(0));
    });

    test('case-insensitive match', () {
      expect(CommandPaletteSearcher.score('PD', 'prod-db'), greaterThan(0));
    });
  });

  group('CommandPaletteSearcher.search', () {
    late List<CommandItem> items;

    setUp(() {
      items = [
        CommandItem(
          id: '1',
          title: 'prod-db',
          subtitle: '',
          icon: Icons.dns,
          type: CommandType.host,
          execute: () {},
        ),
        CommandItem(
          id: '2',
          title: 'padding',
          subtitle: '',
          icon: Icons.dns,
          type: CommandType.host,
          execute: () {},
        ),
        CommandItem(
          id: '3',
          title: 'staging',
          subtitle: '',
          icon: Icons.dns,
          type: CommandType.host,
          execute: () {},
        ),
      ];
    });

    test('empty query returns all items unchanged', () {
      final results = CommandPaletteSearcher.search('', items);
      expect(results.length, 3);
    });

    test('filters out non-matching items', () {
      final results = CommandPaletteSearcher.search('pd', items);
      final titles = results.map((r) => r.title).toList();
      expect(titles, isNot(contains('staging')));
    });

    test('sorts by score descending — prod-db before padding for query "pd"', () {
      final results = CommandPaletteSearcher.search('pd', items);
      expect(results.first.title, 'prod-db');
    });
  });

  group('CommandPaletteSearcher.highlightSpans', () {
    test('empty query returns single non-match span for full text', () {
      final spans = CommandPaletteSearcher.highlightSpans('', 'prod-db');
      expect(spans.length, 1);
      expect(spans.first.$1, 'prod-db');
      expect(spans.first.$2, false);
    });

    test('matched chars are marked as match spans', () {
      final spans = CommandPaletteSearcher.highlightSpans('pd', 'prod-db');
      final matchedChars = spans.where((s) => s.$2).map((s) => s.$1).join();
      expect(matchedChars, 'pd');
    });

    test('full text is preserved across all spans', () {
      final spans = CommandPaletteSearcher.highlightSpans('pd', 'prod-db');
      final full = spans.map((s) => s.$1).join();
      expect(full, 'prod-db');
    });
  });

  group('CommandPaletteDialog', () {
    late List<CommandItem> hosts;
    bool connected = false;

    setUp(() {
      connected = false;
      hosts = [
        CommandItem(
          id: 'h1',
          title: 'prod-db',
          subtitle: 'root@prod-db:22',
          icon: Icons.dns,
          type: CommandType.host,
          execute: () => connected = true,
        ),
        CommandItem(
          id: 'h2',
          title: 'staging',
          subtitle: 'root@staging:22',
          icon: Icons.dns,
          type: CommandType.host,
          execute: () {},
        ),
      ];
    });

    Widget makeDialog(List<CommandItem> items) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => CommandPaletteDialog(items: items),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('shows search field and all items on open', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      // Titles are rendered as RichText; check subtitles (plain Text widgets) instead
      expect(find.text('root@prod-db:22'), findsOneWidget);
      expect(find.text('root@staging:22'), findsOneWidget);
    });

    testWidgets('filters items when query is typed', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'prod');
      await tester.pump();
      expect(find.text('root@prod-db:22'), findsOneWidget);
      expect(find.text('root@staging:22'), findsNothing);
    });

    testWidgets('Escape closes the dialog', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandPaletteDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPaletteDialog), findsNothing);
    });

    testWidgets('Enter executes first item and closes dialog', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(connected, true);
    });
  });
}
