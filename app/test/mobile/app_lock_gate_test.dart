import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
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

  testWidgets('lock screen: wording, FButton >= 44 px, nothing behind it',
      (tester) async {
    await _pump(tester, enabled: true, auth: () async => false);
    expect(find.text('YourSSH is locked'), findsOneWidget);
    expect(find.byType(FButton), findsOneWidget);
    final size = tester.getSize(find.byType(FButton));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(find.byKey(_childKey), findsNothing);
    expect(find.byKey(_childKey, skipOffstage: false), findsNothing);
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
}
