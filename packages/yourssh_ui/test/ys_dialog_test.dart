import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _host(void Function(BuildContext) onTap) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) =>
      FTheme(data: ysThemeData(), child: FToaster(child: child!)),
  home: Scaffold(
    body: Builder(
      builder: (c) =>
          TextButton(onPressed: () => onTap(c), child: const Text('go')),
    ),
  ),
);

/// Taps the 'go' button to open the dialog and waits for it to settle.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  group('showYsConfirm', () {
    testWidgets('returns true on confirm', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(
            c,
            title: 'Title',
            message: 'Body text',
            confirmLabel: 'Yes',
          );
        }),
      );
      await _open(tester);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Body text'), findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('Title'), findsNothing);
    });

    testWidgets('returns false on cancel', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(c, title: 'T', message: 'M');
        }),
      );
      await _open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('returns false on barrier tap', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(c, title: 'T', message: 'M');
        }),
      );
      await _open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(find.text('T'), findsNothing);
    });

    testWidgets('destructive variant renders and confirms', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(
            c,
            title: 'Delete?',
            message: 'Gone forever',
            confirmLabel: 'Delete',
            destructive: true,
          );
        }),
      );
      await _open(tester);
      final button = tester.widget<FButton>(
        find.ancestor(of: find.text('Delete'), matching: find.byType(FButton)),
      );
      expect(button.variant, FButtonVariant.destructive);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('destructive: Enter does not confirm (safe default focus)', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(
            c,
            title: 'Delete?',
            message: 'M',
            confirmLabel: 'Delete',
            destructive: true,
          );
        }),
      );
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('non-destructive: Enter confirms', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(c, title: 'T', message: 'M');
        }),
      );
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('Escape closes and returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((c) async {
          result = await showYsConfirm(c, title: 'T', message: 'M');
        }),
      );
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(find.text('T'), findsNothing);
    });
  });

  group('YsDialog layout', () {
    Future<List<Rect>> openWith(WidgetTester tester, List<String> labels) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          (c) => showYsDialog<void>(
            c,
            builder: (ctx) => YsDialog(
              title: 'T',
              body: const Text('x'),
              actions: [
                for (final l in labels)
                  FButton(onPress: () => Navigator.pop(ctx), child: Text(l)),
              ],
            ),
          ),
        ),
      );
      await _open(tester);
      return [
        for (final l in labels)
          tester.getRect(
            find.ancestor(of: find.text(l), matching: find.byType(FButton)),
          ),
      ];
    }

    testWidgets('three short actions share one row', (tester) async {
      final r = await openWith(tester, ['Cancel', 'Discard', 'Save all']);
      expect(r[1].top, r[0].top);
      expect(r[2].top, r[0].top);
    });

    testWidgets('long labels wrap but stay content-sized and inside', (
      tester,
    ) async {
      final labels = [
        'Long label one',
        'Long label two',
        'Long label three',
      ];
      final r = await openWith(tester, labels);
      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byType(FDialog),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect({for (final b in r) b.top}.length, greaterThan(1));
      for (final b in r) {
        expect(b.left, greaterThanOrEqualTo(dialog.left));
        expect(b.right, lessThanOrEqualTo(dialog.right));
        expect(b.width, lessThan(dialog.width));
      }
    });

    testWidgets('actions share one row and are content-sized', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host((c) => showYsConfirm(
          c,
          title: 'Delete?',
          message: 'Gone forever',
          confirmLabel: 'Delete',
          destructive: true,
        )),
      );
      await _open(tester);
      Rect rect(String label) => tester.getRect(
        find.ancestor(of: find.text(label), matching: find.byType(FButton)),
      );
      final cancel = rect('Cancel');
      final del = rect('Delete');
      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byType(FDialog),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(cancel.top, del.top);
      expect(cancel.right, lessThan(del.left));
      expect(cancel.width, lessThan(dialog.width / 2));
      expect(del.width, lessThan(dialog.width / 2));
      // Right-aligned, and the dialog hugs its short content.
      expect(del.right, lessThanOrEqualTo(dialog.right));
      expect(dialog.width, lessThan(560));
    });
  });

  testWidgets('tall scrollable body fits the dialog (no overflow)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        (c) => showYsDialog<void>(
          c,
          builder: (ctx) => YsDialog(
            title: 'Pick',
            body: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 40; i++)
                      ListTile(dense: true, title: Text('item $i')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _open(tester);
    expect(find.text('item 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('showYsDialog', () {
    testWidgets('non-dismissible dialog ignores barrier tap and Escape', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          (c) => showYsDialog<void>(
            c,
            barrierDismissible: false,
            builder: (ctx) => YsDialog(
              title: 'Stuck',
              actions: [
                FButton(
                  onPress: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
      await _open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Stuck'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Stuck'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Stuck'), findsNothing);
    });

    testWidgets('renders on the root navigator inside FTheme', (tester) async {
      BuildContext? dialogContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ysMaterialTheme(),
          builder: (context, child) =>
              FTheme(data: ysThemeData(), child: FToaster(child: child!)),
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: Builder(
                  builder: (c) => TextButton(
                    onPressed: () => showYsDialog<void>(
                      c,
                      builder: (ctx) {
                        dialogContext = ctx;
                        return YsDialog(
                          title: 'Deep',
                          body: const Text('inside'),
                          actions: [
                            FButton(
                              onPress: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        );
                      },
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _open(tester);
      expect(find.text('Deep'), findsOneWidget);
      expect(find.text('inside'), findsOneWidget);
      // Route lives on the root navigator, not the nested one.
      expect(
        Navigator.of(dialogContext!),
        same(Navigator.of(dialogContext!, rootNavigator: true)),
      );
      // The pushing context sat inside a nested Navigator, so the dialog is
      // not on it: the nested page is still the only route there.
      final nested = Navigator.of(tester.element(find.text('go')));
      expect(nested, isNot(same(Navigator.of(dialogContext!))));
      // FTheme is inherited by the dialog content.
      expect(FTheme.of(dialogContext!).colors.card, YsColors.card);
    });
  });

  testWidgets('YsDialogFrame wraps its child with card decoration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ysMaterialTheme(),
        builder: (context, child) =>
            FTheme(data: ysThemeData(), child: FToaster(child: child!)),
        home: const Scaffold(
          body: Center(child: YsDialogFrame(child: Text('framed'))),
        ),
      ),
    );
    expect(find.text('framed'), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(YsDialogFrame),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final deco = box.decoration as ShapeDecoration;
    expect(deco.color, YsColors.card);
  });
}
