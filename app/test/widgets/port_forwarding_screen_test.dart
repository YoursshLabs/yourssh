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
}
