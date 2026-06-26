import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/mobile/screens/mobile_add_host_screen.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(HostProvider hosts, Widget child) => MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: hosts),
            ChangeNotifierProvider(create: (_) => KeyProvider()),
          ],
          child: child,
        ),
      );

  testWidgets('saving creates a host in the provider', (tester) async {
    final hosts = HostProvider(StorageService());
    await tester.pumpWidget(wrap(hosts, const MobileAddHostScreen()));

    await tester.enterText(find.byKey(const Key('host-label')), 'edge-1');
    await tester.enterText(find.byKey(const Key('host-address')), '192.168.1.9');
    await tester.enterText(find.byKey(const Key('host-username')), 'pi');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
        hosts.allHosts
            .any((h) => h.label == 'edge-1' && h.host == '192.168.1.9'),
        isTrue);
  });

  testWidgets('edit mode prefills fields and updates the host in place',
      (tester) async {
    final hosts = HostProvider(StorageService());
    final existing = Host(
      label: 'Old Name',
      host: '10.0.0.5',
      port: 2222,
      username: 'root',
      tags: const ['prod'],
    );
    await hosts.addHost(existing);

    await tester
        .pumpWidget(wrap(hosts, MobileAddHostScreen(existing: existing)));

    // Title reflects edit mode and fields are pre-filled.
    expect(find.text('Edit host'), findsOneWidget);
    expect(find.text('Old Name'), findsOneWidget);
    expect(find.text('10.0.0.5'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('host-label')), 'New Name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Updated in place (no new host) and unrelated fields preserved.
    expect(hosts.allHosts.length, 1);
    final updated = hosts.allHosts.single;
    expect(updated.id, existing.id);
    expect(updated.label, 'New Name');
    expect(updated.port, 2222);
    expect(updated.tags, ['prod']);
  });
}
