import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yourssh/services/p2p_sync_service.dart';
import 'package:yourssh/widgets/qr_export_dialog.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakeSync extends P2PSyncService {
  _FakeSync(this.ifaces);
  final List<NetworkInterfaceInfo> ifaces;
  var stopped = 0;

  @override
  Future<List<NetworkInterfaceInfo>> getLocalInterfaces() async => ifaces;

  @override
  Future<String> startServer({
    required String encryptedPayload,
    required String hostAddress,
  }) async => 'http://$hostAddress:1/sync';

  @override
  Future<void> stop() async => stopped++;
}

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
              barrierDismissible: false,
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

  testWidgets('Escape closes the dialog like Cancel (barrier stays modal)',
      (tester) async {
    await pump(tester);
    expect(find.byType(QrExportDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(QrExportDialog), findsNothing);
  });

  testWidgets('Escape stops the LAN server and the countdown', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final svc = _FakeSync(const [
      NetworkInterfaceInfo(name: 'en0', address: '192.168.1.5'),
    ]);
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (ctx) => FButton(
            onPress: () => showYsDialog(
              ctx,
              barrierDismissible: false,
              builder: (_) => QrExportDialog(
                getPayload: () async => '{}',
                service: svc,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(QrImageView), findsOneWidget);
    final before = svc.stopped;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QrExportDialog), findsNothing);
    expect(svc.stopped, greaterThan(before));
    // No pending countdown timer left behind (the harness asserts on exit).
  });

  testWidgets('with interfaces loaded: select, QR and copy action present',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final svc = _FakeSync(const [
      NetworkInterfaceInfo(name: 'en0', address: '192.168.1.5'),
      NetworkInterfaceInfo(name: 'en1', address: '10.0.0.5'),
    ]);
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (ctx) => FButton(
            onPress: () => showYsDialog(
              ctx,
              builder: (_) =>
                  QrExportDialog(getPayload: () async => '{}', service: svc),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Encryption runs async; give it real time, then pump.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('qr-export-interface')), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Copy transfer code'), findsOneWidget);
    expect(find.text('Waiting for device to scan...'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(svc.stopped, greaterThan(0));
  });
}
