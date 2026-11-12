import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh/widgets/path_breadcrumb.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show YsColors;

/// forui buttons and checkboxes settle their press feedback 100 ms after a
/// tap; pump past it so no timer outlives the test.
const _pressFeedback = Duration(milliseconds: 200);

Widget _harness(
  List<PathCrumb> crumbs,
  ValueChanged<String> onNavigate, {
  String? editablePath,
}) {
  return MaterialApp(
    builder: ysRootBuilder,
    home: Scaffold(
      body: PathBreadcrumb(
        crumbs: crumbs,
        onNavigate: onNavigate,
        editablePath: editablePath,
      ),
    ),
  );
}

void main() {
  group('posixCrumbs', () {
    test('root path yields a single root crumb', () {
      expect(posixCrumbs('/'), [(label: '/', path: '/')]);
    });

    test('nested path yields root plus one crumb per segment', () {
      expect(posixCrumbs('/home/user/logs'), [
        (label: '/', path: '/'),
        (label: 'home', path: '/home'),
        (label: 'user', path: '/home/user'),
        (label: 'logs', path: '/home/user/logs'),
      ]);
    });

    test('trailing slash is ignored', () {
      expect(posixCrumbs('/var/www/'), [
        (label: '/', path: '/'),
        (label: 'var', path: '/var'),
        (label: 'www', path: '/var/www'),
      ]);
    });
  });

  group('PathBreadcrumb', () {
    testWidgets('renders every crumb label', (tester) async {
      await tester.pumpWidget(_harness(posixCrumbs('/home/user'), (_) {}));
      expect(find.text('/'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('user'), findsOneWidget);
    });

    testWidgets('tapping a crumb navigates to its path', (tester) async {
      String? navigated;
      await tester.pumpWidget(
          _harness(posixCrumbs('/home/user/logs'), (p) => navigated = p));
      await tester.tap(find.text('home'));
      expect(navigated, '/home');
      await tester.pump(_pressFeedback);
    });

    testWidgets('tapping the root crumb navigates to /', (tester) async {
      String? navigated;
      await tester.pumpWidget(
          _harness(posixCrumbs('/home/user'), (p) => navigated = p));
      await tester.tap(find.text('/'));
      expect(navigated, '/');
      await tester.pump(_pressFeedback);
    });

    testWidgets('last crumb is highlighted as current', (tester) async {
      await tester.pumpWidget(_harness(posixCrumbs('/home/user'), (_) {}));
      // Effective style: the crumb's DefaultTextStyle merged with the Text's.
      TextStyle style(String label) =>
          DefaultTextStyle.of(tester.element(find.text(label)))
              .style
              .merge(tester.widget<Text>(find.text(label)).style);
      final current = style('user');
      final parent = style('home');
      expect(current.color, YsColors.foreground);
      expect(current.fontWeight, FontWeight.w500);
      expect(parent.color, YsColors.mutedForeground);
    });
  });

  group('PathBreadcrumb path editing', () {
    testWidgets('no edit affordance when editablePath is null', (tester) async {
      await tester.pumpWidget(_harness(posixCrumbs('/home'), (_) {}));
      expect(find.byTooltip('Go to path'), findsNothing);
    });

    testWidgets('tapping the edit affordance reveals a text field seeded '
        'with the current path', (tester) async {
      await tester.pumpWidget(
          _harness(posixCrumbs('/home/user'), (_) {}, editablePath: '/home/user'));
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.byTooltip('Go to path'));
      await tester.pump(_pressFeedback);

      expect(find.byType(EditableText), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.controller.text, '/home/user');
    });

    testWidgets('submitting a typed path navigates to it', (tester) async {
      String? navigated;
      await tester.pumpWidget(_harness(
          posixCrumbs('/home'), (p) => navigated = p,
          editablePath: '/home'));
      await tester.tap(find.byTooltip('Go to path'));
      await tester.pump(_pressFeedback);

      await tester.enterText(find.byType(EditableText), '/var/log');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(navigated, '/var/log');
      // Editor collapses back to the breadcrumb after navigating.
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('blank submission does not navigate', (tester) async {
      String? navigated;
      await tester.pumpWidget(_harness(
          posixCrumbs('/home'), (p) => navigated = p,
          editablePath: '/home'));
      await tester.tap(find.byTooltip('Go to path'));
      await tester.pump(_pressFeedback);

      await tester.enterText(find.byType(EditableText), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(navigated, isNull);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('Escape cancels editing without navigating', (tester) async {
      String? navigated;
      await tester.pumpWidget(_harness(
          posixCrumbs('/home'), (p) => navigated = p,
          editablePath: '/home'));
      await tester.tap(find.byTooltip('Go to path'));
      await tester.pump(_pressFeedback);
      expect(find.byType(EditableText), findsOneWidget);

      await tester.enterText(find.byType(EditableText), '/etc');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(navigated, isNull);
      expect(find.byType(EditableText), findsNothing);
      // Breadcrumb is back.
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('PathBreadcrumb long paths', () {
    testWidgets('a short path starts at the leading edge', (tester) async {
      await tester.pumpWidget(_harness(posixCrumbs('/home'), (_) {}));
      expect(tester.getTopLeft(find.text('/')).dx, lessThan(20));
    });

    testWidgets('a long path shows the current folder, not the root',
        (tester) async {
      final path = '/${[for (var i = 0; i < 30; i++) 'segment$i'].join('/')}';
      await tester.pumpWidget(MaterialApp(
        builder: ysRootBuilder,
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: PathBreadcrumb(crumbs: posixCrumbs(path), onNavigate: (_) {}),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      final current = tester.getRect(find.text('segment29'));
      expect(current.right, lessThanOrEqualTo(300));
      expect(current.left, greaterThanOrEqualTo(0));
    });
  });
}
