import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';

const _childKey = Key('locked-child');

Future<void> _pump(WidgetTester tester,
    {required bool enabled, required Future<bool> Function() auth}) async {
  await tester.pumpWidget(MaterialApp(
    home: AppLockGate(
      enabledOverride: enabled,
      authenticator: auth,
      child: const Scaffold(body: SizedBox(key: _childKey)),
    ),
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
}
