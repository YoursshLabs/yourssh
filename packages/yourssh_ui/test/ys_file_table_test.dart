import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class _Row {
  const _Row(this.name, {this.size = 0, this.dir = false});
  final String name;
  final int size;
  final bool dir;

  @override
  String toString() => name;
}

const _alpha = _Row('alpha', dir: true);
const _bravo = _Row('bravo', size: 10);
const _charlie = _Row('charlie', size: 30);
const _delta = _Row('delta', size: 20);
const _rows = [_alpha, _bravo, _charlie, _delta];

/// One `onSelect` call.
typedef _Sel = ({String name, bool additive, bool range});

/// Stable column list (the table reuses row widgets while it is unchanged).
final List<YsColumn<_Row>> _columns = [
  YsColumn<_Row>(
    id: 'name',
    label: 'Name',
    sortable: true,
    flex: 3,
    cell: (_, r) => Text(r.name),
  ),
  YsColumn<_Row>(
    id: 'size',
    label: 'Size',
    sortable: true,
    width: 70,
    numeric: true,
    cell: (_, r) => Text('${r.size} B'),
  ),
  YsColumn<_Row>(
    id: 'kind',
    label: 'Kind',
    width: 70,
    minTableWidth: 500,
    cell: (_, r) => Text(r.dir ? 'folder' : 'file'),
  ),
];

class _Log {
  final selects = <_Sel>[];
  final opens = <String>[];
  final menus = <(String, Offset)>[];
  final sorts = <YsSort>[];
  final selectAll = <bool>[];

  void clear() {
    selects.clear();
    opens.clear();
    menus.clear();
    sorts.clear();
    selectAll.clear();
  }
}

Widget _wrap(Widget child, {double width = 800, double height = 400}) =>
    MaterialApp(
      theme: ysMaterialTheme(),
      builder: (context, child) => FTheme(data: ysThemeData(), child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

YsFileTable<_Row> _table(
  _Log log, {
  List<_Row> rows = _rows,
  List<YsColumn<_Row>>? columns,
  Set<_Row> selected = const {},
  YsSort? sort,
  bool checkboxes = false,
  bool openOnTap = false,
  bool draggable = false,
  bool autofocus = false,
  ScrollController? controller,
}) => YsFileTable<_Row>(
  rows: rows,
  columns: columns ?? _columns,
  selected: selected,
  sort: sort,
  checkboxes: checkboxes,
  openOnTap: openOnTap,
  draggable: draggable,
  autofocus: autofocus,
  controller: controller,
  rowLabel: (r) => r.name,
  selectAllKey: const Key('select-all'),
  onSelect: (r, {additive = false, range = false}) =>
      log.selects.add((name: r.name, additive: additive, range: range)),
  onOpen: (r) => log.opens.add(r.name),
  onContextMenu: (r, p) => log.menus.add((r.name, p)),
  onSort: log.sorts.add,
  onSelectAll: log.selectAll.add,
);

/// forui controls (checkboxes, sortable headers) settle their press
/// feedback 100 ms after the tap.
const _pressFeedback = Duration(milliseconds: 200);

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// Taps [text] with [modifier] held down.
Future<void> _modTap(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  String text,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.tap(find.text(text));
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  group('layout', () {
    testWidgets('rows are 28 px and the header lists the columns', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_table(_Log())));
      expect(kYsFileTableRowHeight, 28);
      expect(
        tester.getSize(find.byKey(const ValueKey('ys-file-row-0'))).height,
        28,
      );
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Kind'), findsOneWidget);
      for (final r in _rows) {
        expect(find.text(r.name), findsOneWidget);
      }
    });

    testWidgets('a column hides when the table is narrower than its '
        'minTableWidth', (tester) async {
      await tester.pumpWidget(_wrap(_table(_Log()), width: 400));
      expect(find.text('Kind'), findsNothing);
      expect(find.text('folder'), findsNothing);
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('selected rows are tinted amber', (tester) async {
      await tester.pumpWidget(_wrap(_table(_Log(), selected: {_bravo})));
      Color? tint(int i) {
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(ValueKey('ys-file-row-$i')),
            matching: find.byKey(const ValueKey('ys-file-row-surface')),
          ),
        );
        return (box.decoration as BoxDecoration).color;
      }

      expect(tint(1), kYsFileTableSelectedColor);
      expect(tint(0), isNot(kYsFileTableSelectedColor));
    });

    testWidgets('a long name ellipsizes instead of overflowing', (
      tester,
    ) async {
      final long = _Row('x' * 200);
      await tester.pumpWidget(_wrap(_table(_Log(), rows: [long]), width: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('mouse selection', () {
    testWidgets('plain click selects only; Cmd/Ctrl-click adds; '
        'Shift-click selects a range', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log)));

      await tester.tap(find.text('bravo'));
      await tester.pump();
      await _modTap(tester, LogicalKeyboardKey.metaLeft, 'charlie');
      await _modTap(tester, LogicalKeyboardKey.controlLeft, 'alpha');
      await _modTap(tester, LogicalKeyboardKey.shiftLeft, 'delta');

      expect(log.selects, [
        (name: 'bravo', additive: false, range: false),
        (name: 'charlie', additive: true, range: false),
        (name: 'alpha', additive: true, range: false),
        (name: 'delta', additive: false, range: true),
      ]);
      expect(log.opens, isEmpty);
    });

    testWidgets('double-click opens the row', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log)));

      await tester.tap(find.text('alpha'));
      await tester.tap(find.text('alpha'));
      await tester.pump();

      expect(log.opens, ['alpha']);
      expect(log.selects.map((s) => s.name), [
        'alpha',
      ], reason: 'the first click selects, the second opens');
    });

    testWidgets('two clicks further apart than the double-click timeout '
        'are two selections', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log)));

      await tester.tap(find.text('alpha'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('alpha'));
      await tester.pump();

      expect(log.opens, isEmpty);
      expect(log.selects.length, 2);
    });

    testWidgets('openOnTap opens on a single click without selecting', (
      tester,
    ) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log, openOnTap: true)));

      await tester.tap(find.text('charlie'));
      await tester.pump();

      expect(log.opens, ['charlie']);
      expect(log.selects, isEmpty);
    });

    testWidgets('right-click reports the row and the pointer position '
        'without changing the selection', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log)));

      final at = tester.getCenter(find.text('charlie'));
      await tester.tapAt(at, buttons: kSecondaryButton);
      await tester.pump();

      expect(log.menus, [('charlie', at)]);
      expect(log.selects, isEmpty);
      expect(log.opens, isEmpty);
    });
  });

  group('checkboxes', () {
    testWidgets(
      'one per row plus select-all; a row checkbox toggles that row',
      (tester) async {
        final log = _Log();
        await tester.pumpWidget(_wrap(_table(log, checkboxes: true)));

        expect(find.byType(FCheckbox), findsNWidgets(_rows.length + 1));
        // Index 0 is the header; rows follow in order.
        await tester.tap(find.byType(FCheckbox).at(3));
        await tester.pump(_pressFeedback);

        expect(log.selects, [(name: 'charlie', additive: true, range: false)]);
      },
    );

    testWidgets('select-all selects everything, or clears a full selection', (
      tester,
    ) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log, checkboxes: true)));
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump(_pressFeedback);
      expect(log.selectAll, [true]);

      log.clear();
      await tester.pumpWidget(
        _wrap(_table(log, checkboxes: true, selected: _rows.toSet())),
      );
      await tester.tap(find.byKey(const Key('select-all')));
      await tester.pump(_pressFeedback);
      expect(log.selectAll, [false]);
    });
  });

  group('keyboard', () {
    testWidgets('Down then Enter opens the first row (keyboard only)', (
      tester,
    ) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log, autofocus: true)));
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(log.opens, ['alpha']);
      expect(log.selects, isEmpty, reason: 'arrows move the cursor only');
    });

    testWidgets('arrows move the cursor, Space toggles, Shift+arrow extends, '
        'Enter opens', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log)));

      await tester.tap(find.text('alpha')); // focus + cursor on row 0
      await tester.pump(const Duration(milliseconds: 500));
      log.clear();

      await _press(tester, LogicalKeyboardKey.arrowDown); // bravo
      await _press(tester, LogicalKeyboardKey.space);
      await _chord(
        tester,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.arrowDown,
      ); // charlie
      await _press(tester, LogicalKeyboardKey.enter);

      expect(log.selects, [
        (name: 'bravo', additive: true, range: false),
        (name: 'charlie', additive: false, range: true),
      ]);
      expect(log.opens, ['charlie']);

      // The cursor clamps at both ends.
      for (var i = 0; i < 6; i++) {
        await _press(tester, LogicalKeyboardKey.arrowUp);
      }
      await _press(tester, LogicalKeyboardKey.enter);
      for (var i = 0; i < 6; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.enter);
      expect(log.opens, ['charlie', 'alpha', 'delta']);
    });

    testWidgets('Cmd+A and Ctrl+A select all', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log, autofocus: true)));
      await tester.pump();

      await _chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.keyA,
      );
      await _chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyA,
      );

      expect(log.selectAll, [true, true]);
    });

    testWidgets('Shift+F10 opens the context menu for the cursor row', (
      tester,
    ) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log, autofocus: true)));
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _chord(
        tester,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.f10,
      );

      expect(log.menus.map((m) => m.$1), ['bravo']);
      // Anchored at the cursor row.
      final row = tester.getRect(find.byKey(const ValueKey('ys-file-row-1')));
      final at = log.menus.single.$2;
      expect(at.dy, inInclusiveRange(row.top, row.bottom));
      expect(at.dx, inInclusiveRange(row.left, row.right));
    });

    testWidgets('moving the cursor scrolls it into view', (tester) async {
      final rows = [for (var i = 0; i < 100; i++) _Row('row $i')];
      final log = _Log();
      await tester.pumpWidget(
        _wrap(_table(log, rows: rows, autofocus: true), height: 200),
      );
      await tester.pump();

      for (var i = 0; i < 30; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(find.text('row 29'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(log.opens, ['row 29']);
    });
  });

  group('sorting', () {
    testWidgets('the sorted column shows its direction; pressing it flips, '
        'pressing another sorts that one ascending', (tester) async {
      final log = _Log();
      await tester.pumpWidget(_wrap(_table(log, sort: const YsSort('name'))));

      expect(find.byIcon(FLucideIcons.arrowUp), findsOneWidget);

      await tester.tap(find.text('Name'));
      await tester.pump(_pressFeedback);
      await tester.tap(find.text('Size'));
      await tester.pump(_pressFeedback);
      await tester.tap(find.text('Kind')); // not sortable
      await tester.pump(_pressFeedback);

      expect(log.sorts, [
        const YsSort('name', ascending: false),
        const YsSort('size'),
      ]);

      await tester.pumpWidget(
        _wrap(_table(log, sort: const YsSort('size', ascending: false))),
      );
      expect(find.byIcon(FLucideIcons.arrowDown), findsOneWidget);
      expect(find.byIcon(FLucideIcons.arrowUp), findsNothing);
    });

    test('YsSort.next flips the same column and resets for another', () {
      expect(const YsSort('a').next('a'), const YsSort('a', ascending: false));
      expect(const YsSort('a', ascending: false).next('a'), const YsSort('a'));
      expect(const YsSort('a', ascending: false).next('b'), const YsSort('b'));
    });
  });

  group('drag and drop', () {
    testWidgets('a draggable row carries its value to a DragTarget', (
      tester,
    ) async {
      _Row? dropped;
      await tester.pumpWidget(
        MaterialApp(
          theme: ysMaterialTheme(),
          builder: (context, child) =>
              FTheme(data: ysThemeData(), child: child!),
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 400,
                  height: 300,
                  child: _table(_Log(), draggable: true),
                ),
                Expanded(
                  child: DragTarget<_Row>(
                    onAcceptWithDetails: (d) => dropped = d.data,
                    builder: (_, _, _) =>
                        const SizedBox.expand(key: Key('target')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('bravo')),
      );
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(dropped, same(_bravo));
    });
  });

  group('large directories', () {
    final big = [for (var i = 0; i < 5000; i++) _Row('file $i', size: i)];

    testWidgets(
      '5,000 rows: only visible rows are built, while scrolling too',
      (tester) async {
        var builds = 0;
        final columns = [
          YsColumn<_Row>(
            id: 'name',
            label: 'Name',
            cell: (_, r) {
              builds++;
              return Text(r.name);
            },
          ),
        ];
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _wrap(
            _table(_Log(), rows: big, columns: columns, controller: controller),
            height: 600,
          ),
        );

        // ~21 rows fit in 600 px; the list caches a little more off-screen.
        expect(builds, lessThan(60));

        for (final offset in [28.0 * 1000, 28.0 * 2500, 28.0 * 4980]) {
          builds = 0;
          controller.jumpTo(offset);
          await tester.pump();
          expect(builds, lessThan(60), reason: 'jump to $offset');
        }
        expect(find.text('file 4999'), findsOneWidget);
      },
    );

    testWidgets('a selection change rebuilds only the rows it touches', (
      tester,
    ) async {
      var builds = 0;
      final columns = [
        YsColumn<_Row>(
          id: 'name',
          label: 'Name',
          cell: (_, r) {
            builds++;
            return Text(r.name);
          },
        ),
      ];
      Widget build(Set<_Row> selected) => _wrap(
        _table(_Log(), rows: big, columns: columns, selected: selected),
        height: 600,
      );
      await tester.pumpWidget(build(const {}));

      builds = 0;
      await tester.pumpWidget(build({big[3]}));
      expect(builds, 1, reason: 'only row 3 changed');

      builds = 0;
      await tester.pumpWidget(build({big[3], big[5]}));
      expect(builds, 1, reason: 'only row 5 changed');
    });
  });
}
