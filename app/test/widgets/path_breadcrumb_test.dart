import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/path_breadcrumb.dart';

Widget _harness(List<PathCrumb> crumbs, ValueChanged<String> onNavigate) {
  return MaterialApp(
    home: Scaffold(
      body: PathBreadcrumb(crumbs: crumbs, onNavigate: onNavigate),
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
    });

    testWidgets('tapping the root crumb navigates to /', (tester) async {
      String? navigated;
      await tester.pumpWidget(
          _harness(posixCrumbs('/home/user'), (p) => navigated = p));
      await tester.tap(find.text('/'));
      expect(navigated, '/');
    });

    testWidgets('last crumb is highlighted as current', (tester) async {
      await tester.pumpWidget(_harness(posixCrumbs('/home/user'), (_) {}));
      final current = tester.widget<Text>(find.text('user'));
      final parent = tester.widget<Text>(find.text('home'));
      expect(current.style!.color, const Color(0xFFD4D4D4));
      expect(current.style!.fontWeight, FontWeight.w500);
      expect(parent.style!.color, const Color(0xFF666666));
    });
  });
}
