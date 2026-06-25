import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/services/storage_service.dart';

Future<void> _pump(WidgetTester tester, HostProvider hosts) async {
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider.value(
      value: hosts,
      child: MobileHostsScreen(onConnected: () {}, onAddHost: () {}),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('shows empty state with no hosts', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.textContaining('No hosts'), findsOneWidget);
  });
}
