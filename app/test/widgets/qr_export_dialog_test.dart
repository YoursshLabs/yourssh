import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/qr_export_dialog.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (ctx) => FButton(
            onPress: () => showYsDialog(
              ctx,
              builder: (_) => QrExportDialog(getPayload: () async => '{}'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows title, progress and Cancel while initialising',
      (tester) async {
    await pump(tester);
    expect(find.text('Export via QR'), findsOneWidget);
    expect(find.text('Initializing...'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel closes the dialog', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(QrExportDialog), findsNothing);
  });
}
