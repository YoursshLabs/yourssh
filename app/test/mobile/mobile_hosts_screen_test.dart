import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Future<void> _pump(WidgetTester tester, HostProvider hosts) async {
  final sessions = SessionProvider(SshService(StorageService()), TabMetadataService());
  await tester.pumpWidget(MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hosts),
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ],
      child: MobileHostsScreen(onConnected: () {}, onAddHost: () {}),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty state shows add CTA', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.textContaining('No hosts'), findsOneWidget);
  });

  testWidgets('renders a HostCard per host', (tester) async {
    final hosts = HostProvider(StorageService());
    await hosts.addHost(Host(label: 'Alpha', host: '1.1.1.1', username: 'root'));
    await hosts.addHost(Host(label: 'Beta', host: '2.2.2.2', username: 'root'));
    await _pump(tester, hosts);
    expect(find.byType(HostCard), findsNWidgets(2));
  });

  testWidgets('lists hosts and filters by search', (tester) async {
    final hosts = HostProvider(StorageService());
    await hosts.addHost(Host(label: 'prod-web', host: '10.0.0.1', username: 'root'));
    await hosts.addHost(Host(label: 'db-1', host: '10.0.0.2', username: 'admin'));

    await _pump(tester, hosts);
    expect(find.text('prod-web'), findsOneWidget);
    expect(find.text('db-1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'prod');
    await tester.pumpAndSettle();
    expect(find.text('prod-web'), findsOneWidget);
    expect(find.text('db-1'), findsNothing);
  });
}
