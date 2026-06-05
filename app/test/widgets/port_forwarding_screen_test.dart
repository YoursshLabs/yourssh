import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/services/port_forward_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/port_forwarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(PortForwardProvider, Widget)> build() async {
    final provider = PortForwardProvider();
    await provider.ready;
    final service = PortForwardService(
      acquireTransport: (_) async => throw UnimplementedError(),
      resolveHost: (_) => null,
      onStatus: provider.setStatus,
      onConnections: provider.setConnections,
    );
    final widget = MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => HostProvider(StorageService())),
        Provider.value(value: service),
      ],
      child: const MaterialApp(home: Scaffold(body: PortForwardingScreen())),
    );
    return (provider, widget);
  }

  testWidgets('rule row shows start toggle, error line and conn chip',
      (tester) async {
    final (provider, widget) = await build();
    final fwd = PortForward(
        label: 'db tunnel',
        type: ForwardType.local,
        localPort: 8080,
        remoteHost: 'db',
        remotePort: 5432);
    await provider.add(fwd);

    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('db tunnel'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    provider.setStatus(fwd.id, ForwardStatus.error,
        error: 'Port 8080 already in use');
    await tester.pump();
    expect(find.text('Port 8080 already in use'), findsOneWidget);

    provider.setStatus(fwd.id, ForwardStatus.active);
    provider.setConnections(fwd.id, 3);
    await tester.pump();
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.text('3 conn'), findsOneWidget);
  });

  testWidgets('tapping a rule opens the edit panel prefilled', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'edit me',
        type: ForwardType.local,
        localPort: 9090,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('edit me'));
    await tester.pump();

    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'edit me'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Auto-start on launch'), findsOneWidget);
  });

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await gesture.down(tester.getCenter(finder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-click opens context menu with Duplicate/Edit/Delete',
      (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'menu me',
        type: ForwardType.local,
        localPort: 7000,
        remoteHost: 'db',
        remotePort: 5432));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('menu me'));

    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Duplicate adds a copy with new id, "(copy)" label, autoStart off',
      (tester) async {
    final (provider, widget) = await build();
    final original = PortForward(
        label: 'db tunnel',
        type: ForwardType.local,
        localHost: '127.0.0.1',
        localPort: 8080,
        remoteHost: 'db.internal',
        remotePort: 5432,
        hostId: 'h1',
        autoStart: true);
    await provider.add(original);

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('db tunnel'));
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(provider.forwards, hasLength(2));
    final copy =
        provider.forwards.firstWhere((f) => f.id != original.id);
    expect(copy.label, 'db tunnel (copy)');
    expect(copy.type, original.type);
    expect(copy.localHost, original.localHost);
    expect(copy.localPort, original.localPort);
    expect(copy.remoteHost, original.remoteHost);
    expect(copy.remotePort, original.remotePort);
    expect(copy.hostId, original.hostId);
    expect(copy.autoStart, isFalse);
    expect(copy.status, ForwardStatus.idle);
  });

  testWidgets('Edit menu entry opens the edit panel', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'edit via menu',
        type: ForwardType.local,
        localPort: 9001,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('edit via menu'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
  });

  testWidgets('Delete menu entry removes the rule', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'delete via menu',
        type: ForwardType.local,
        localPort: 9002,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('delete via menu'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(provider.forwards, isEmpty);
  });
}
