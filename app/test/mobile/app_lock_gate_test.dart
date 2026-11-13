import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

const _childKey = Key('locked-child');

Future<void> _pump(WidgetTester tester,
    {required bool enabled, required Future<bool> Function() auth}) async {
  await tester.pumpWidget(ysTestApp(
    AppLockGate(
      enabledOverride: enabled,
      authenticator: auth,
      child: const Scaffold(body: SizedBox(key: _childKey)),
    ),
    touch: true,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('disabled shows child immediately', (tester) async {
    await _pump(tester, enabled: false, auth: () async => false);
    expect(find.byKey(_childKey), findsOneWidget);
  });

  testWidgets('enabled + success unlocks to child', (tester) async {
    await _pump(tester, enabled: true, auth: () async => true);
    expect(find.byKey(_childKey), findsOneWidget);
  });

  testWidgets('enabled + failure keeps the lock screen', (tester) async {
    await _pump(tester, enabled: true, auth: () async => false);
    expect(find.byKey(_childKey), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('lock screen: wording, FButton >= 44 px, child offstage',
      (tester) async {
    await _pump(tester, enabled: true, auth: () async => false);
    expect(find.text('YourSSH is locked'), findsOneWidget);
    expect(find.byType(FButton), findsOneWidget);
    final size = tester.getSize(find.byType(FButton));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
    // The child stays mounted (sessions/routes survive) but offstage.
    expect(find.byKey(_childKey), findsNothing);
    expect(find.byKey(_childKey, skipOffstage: false), findsOneWidget);
  });

  testWidgets('Unlock retries auth and unlocks on success', (tester) async {
    var calls = 0;
    await _pump(tester, enabled: true, auth: () async => ++calls >= 2);
    expect(find.byKey(_childKey), findsNothing);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(_childKey), findsOneWidget);
  });

  group('gate in MaterialApp.builder covers every route', () {
    final nav = GlobalKey<NavigatorState>();
    var calls = 0;
    var allow = false;

    Future<void> pumpApp(WidgetTester t) async {
      calls = 0;
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: ysMaterialTheme(),
        // Mirrors mobile_app.dart: gate outside the toaster so toasts stay
        // under the lock too.
        builder: (c, child) => AppLockGate(
          enabledOverride: true,
          authenticator: () async {
            calls++;
            return allow;
          },
          child: ysRootBuilderTouch(c, child),
        ),
        home: const Text('home'),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('pushed route is covered while locked and survives unlock',
        (t) async {
      allow = false;
      await pumpApp(t);
      nav.currentState!
          .push(MaterialPageRoute(builder: (_) => const Text('terminal')));
      await t.pumpAndSettle();
      expect(find.text('YourSSH is locked'), findsOneWidget);
      expect(find.text('terminal'), findsNothing);
      expect(find.text('terminal', skipOffstage: false), findsOneWidget);
      allow = true;
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('terminal'), findsOneWidget);
    });

    testWidgets('backgrounding re-locks over the current route, no prompt loop',
        (t) async {
      allow = true;
      await pumpApp(t);
      nav.currentState!
          .push(MaterialPageRoute(builder: (_) => const Text('terminal')));
      await t.pumpAndSettle();
      expect(find.text('terminal'), findsOneWidget);
      expect(calls, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.text('terminal'), findsNothing);
      expect(find.text('YourSSH is locked'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('terminal'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('a dialog on the root navigator is covered while locked',
        (t) async {
      allow = false;
      await pumpApp(t);
      showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(content: Text('secret dialog')));
      await t.pumpAndSettle();
      expect(find.text('YourSSH is locked'), findsOneWidget);
      expect(find.text('secret dialog'), findsNothing);
      expect(find.text('secret dialog', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a toast shown while locked does not paint above the lock',
        (t) async {
      allow = false;
      await pumpApp(t);
      showFToast(
          context: nav.currentContext!, title: const Text('secret toast'));
      await t.pumpAndSettle();
      expect(find.text('YourSSH is locked'), findsOneWidget);
      expect(find.text('secret toast'), findsNothing);
    });
  });
}
