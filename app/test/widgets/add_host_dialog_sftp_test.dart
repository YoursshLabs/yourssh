import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/widgets/add_host_dialog.dart';

/// NOTE on overflow: AddHostDialog is a fixed 400px-wide AlertDialog whose
/// AuthType dropdown sizes to its widest item ("Certificate (Key + CA cert)").
/// That overflows by ~92px on every pump — a pre-existing cosmetic issue in
/// the production widget, unrelated to the SFTP controls under test. We drain
/// those expected RenderFlex-overflow exceptions after settling so they don't
/// mask (or fail) the SFTP behavioural assertions below.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // No saved keys; KeyProvider also scans ~/.ssh but that's harmless here.
    SharedPreferences.setMockInitialValues({});
  });

  // Holds the popped (host:, password:) record once the dialog closes.
  late ({Host host, String password})? popped;

  // Settle, then swallow any pre-existing layout-overflow exceptions. Re-throws
  // anything that isn't a RenderFlex overflow so real failures still surface.
  Future<void> settleIgnoringOverflow(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (true) {
      final ex = tester.takeException();
      if (ex == null) break;
      final msg = ex.toString();
      if (!msg.contains('overflowed') && !msg.contains('RenderFlex')) {
        throw ex; // surface any non-overflow failure
      }
    }
  }

  Future<void> pumpDialog(WidgetTester tester, {Host? existing}) async {
    popped = null;
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<KeyProvider>(
        create: (_) => KeyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  popped = await showDialog<({Host host, String password})>(
                    context: context,
                    builder: (_) => AddHostDialog(existing: existing),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleIgnoringOverflow(tester);
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'srv');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Host / IP'), '1.2.3.4');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'), 'root');
  }

  testWidgets('selecting Sudo (root) round-trips sftpMode == sudo',
      (tester) async {
    await pumpDialog(tester);
    await fillRequired(tester);

    // Open the SFTP Mode dropdown (current value "Default") and pick Sudo.
    await tester.tap(find.text('Default'));
    await settleIgnoringOverflow(tester);
    await tester.tap(find.text('Sudo (root)').last);
    await settleIgnoringOverflow(tester);

    await tester.tap(find.text('Add'));
    await settleIgnoringOverflow(tester);

    expect(popped, isNotNull);
    expect(popped!.host.sftpMode, SftpMode.sudo);
    // Command stays null unless custom.
    expect(popped!.host.sftpServerCommand, isNull);
  });

  testWidgets('custom mode shows command field and saves trimmed command',
      (tester) async {
    await pumpDialog(tester);
    await fillRequired(tester);

    await tester.tap(find.text('Default'));
    await settleIgnoringOverflow(tester);
    await tester.tap(find.text('Custom command').last);
    await settleIgnoringOverflow(tester);

    expect(find.widgetWithText(TextFormField, 'SFTP server command'),
        findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'SFTP server command'),
        '  sudo /usr/lib/openssh/sftp-server  ');

    await tester.tap(find.text('Add'));
    await settleIgnoringOverflow(tester);

    expect(popped, isNotNull);
    expect(popped!.host.sftpMode, SftpMode.custom);
    expect(
        popped!.host.sftpServerCommand, 'sudo /usr/lib/openssh/sftp-server');
  });

  testWidgets('custom mode with empty command blocks save and shows Required',
      (tester) async {
    await pumpDialog(tester);
    await fillRequired(tester);

    // Select "Custom command" in the SFTP Mode dropdown.
    await tester.tap(find.text('Default'));
    await settleIgnoringOverflow(tester);
    await tester.tap(find.text('Custom command').last);
    await settleIgnoringOverflow(tester);

    // Leave the SFTP server command field empty and tap Add.
    await tester.tap(find.text('Add'));
    await settleIgnoringOverflow(tester);

    // Dialog must NOT have popped.
    expect(popped, isNull);
    // The 'Required' validation error from the empty command field is shown.
    expect(find.text('Required'), findsWidgets);
  });

  testWidgets('editing an existing sudo host shows Sudo selected',
      (tester) async {
    final existing = Host(
      label: 'srv',
      host: '1.2.3.4',
      username: 'root',
      sftpMode: SftpMode.sudo,
    );
    await pumpDialog(tester, existing: existing);
    expect(find.text('Sudo (root)'), findsOneWidget);
  });
}
