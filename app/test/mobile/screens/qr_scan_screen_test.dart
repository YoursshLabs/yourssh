import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_qr_scan_screen.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

void Function(BarcodeCapture)? _detect;

Widget _fakeScanner(BuildContext c, void Function(BarcodeCapture) onDetect) {
  _detect = onDetect;
  return const ColoredBox(
    key: Key('fake-scanner'),
    color: Colors.black,
    child: SizedBox.expand(),
  );
}

/// Home with a button that opens the scan screen and shows its pop result.
Widget _host() => ChangeNotifierProvider<HostProvider>.value(
      value: HostProvider(StorageService()),
      child: MaterialApp(
        builder: ysRootBuilderTouch,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      final r = await Navigator.of(ctx).push<String>(
                        MaterialPageRoute(
                          builder: (_) => const MobileQrScanScreen(
                            scannerBuilder: _fakeScanner,
                          ),
                        ),
                      );
                      if (r != null) {
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(SnackBar(content: Text(r)));
                      }
                    },
                    child: const Text('open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('smoke: title, scanner view and Back action are present',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Scan transfer QR'), findsOneWidget);
    expect(find.byKey(const Key('fake-scanner')), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    final back = find.descendant(
        of: find.byTooltip('Back'), matching: find.bySubtype<FTappable>());
    expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Back'), findsWidgets);
  });

  testWidgets('Back pops the screen', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileQrScanScreen), findsNothing);
  });

  testWidgets('an invalid code pops with an "Import failed" message',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    _detect!(const BarcodeCapture(barcodes: [Barcode(rawValue: 'not-a-code')]));
    await tester.pumpAndSettle();
    expect(find.byType(MobileQrScanScreen), findsNothing);
    expect(find.textContaining('Import failed'), findsOneWidget);
  });
}
