import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh/widgets/tofu_dialogs.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Opens [dialog] through the production route and returns its result holder.
Future<List<bool?>> _open(WidgetTester tester, Widget dialog) async {
  final result = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: ysRootBuilder,
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result.add(
            await showYsDialog<bool>(
              c,
              barrierDismissible: false,
              builder: (_) => dialog,
            ),
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

FButton _button(WidgetTester tester, String label) => tester.widget<FButton>(
  find.ancestor(of: find.text(label), matching: find.byType(FButton)),
);

/// Challenges arm a 2-minute timeout timer; settle it so the test can end.
Widget _withCleanup(Widget dialog) {
  final challenge = (dialog as dynamic).challenge as TofuChallenge;
  addTearDown(() => challenge.resolve(false));
  return dialog;
}

void main() {
  final cases = <String, ({Widget Function() dialog, String reject, String accept, bool destructive})>{
    'host key changed': (
      dialog: () => HostKeyDialog(
        challenge: HostKeyChallenge(
          host: 'h',
          port: 22,
          keyType: 'ssh-ed25519',
          oldFingerprint: 'SHA256:old',
          newFingerprint: 'SHA256:new',
        ),
      ),
      reject: 'Cancel',
      accept: 'Trust new key',
      destructive: true,
    ),
    'host key type changed': (
      dialog: () => HostKeyDialog(
        challenge: HostKeyChallenge(
          host: 'h',
          port: 22,
          keyType: 'ecdsa-sha2-nistp256',
          oldKeyType: 'ssh-ed25519',
          oldFingerprint: 'SHA256:old',
          newFingerprint: 'SHA256:new',
        ),
      ),
      reject: 'Cancel',
      accept: 'Trust new key',
      destructive: true,
    ),
    'RDP certificate first use': (
      dialog: () => RdpCertDialog(
        challenge: RdpCertChallenge(
          host: 'h',
          port: 3389,
          fingerprint: 'AA:BB',
          isMismatch: false,
        ),
      ),
      reject: 'Reject',
      accept: 'Accept',
      destructive: false,
    ),
    'RDP certificate changed': (
      dialog: () => RdpCertDialog(
        challenge: RdpCertChallenge(
          host: 'h',
          port: 3389,
          fingerprint: 'AA:BB',
          isMismatch: true,
        ),
      ),
      reject: 'Reject',
      accept: 'Trust new cert',
      destructive: true,
    ),
  };

  for (final e in cases.entries) {
    testWidgets('${e.key}: Enter rejects, accept variant matches', (
      tester,
    ) async {
      final result = await _open(tester, _withCleanup(e.value.dialog()));
      expect(_button(tester, e.value.reject).autofocus, isTrue);
      expect(
        _button(tester, e.value.accept).variant,
        e.value.destructive
            ? FButtonVariant.destructive
            : FButtonVariant.primary,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, [false]);
    });

    testWidgets('${e.key}: accept button trusts', (tester) async {
      final result = await _open(tester, _withCleanup(e.value.dialog()));
      await tester.tap(find.text(e.value.accept));
      await tester.pumpAndSettle();
      expect(result, [true]);
    });
  }
}
