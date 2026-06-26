import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/mobile/services/host_reachability_probe.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/mobile_fab.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Future<void> _pump(WidgetTester tester, HostProvider hosts) async {
  final sessions = SessionProvider(SshService(StorageService()), TabMetadataService());
  final probe = HostReachabilityProbe(
    connector: (_, __, ___) async {}, // no-op — no real network in tests
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: buildMobileTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          ChangeNotifierProvider<SessionProvider>.value(value: sessions),
          ChangeNotifierProvider<HostReachabilityProbe>.value(value: probe),
        ],
        child: const MobileHostsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows title "Hosts"', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.text('Hosts'), findsOneWidget);
  });

  testWidgets('renders both host labels and Production section header', (tester) async {
    final hosts = HostProvider(StorageService());
    await hosts.addHost(Host(
      label: 'web-01',
      host: '10.0.0.1',
      username: 'root',
      tags: ['Production'],
    ));
    await hosts.addHost(Host(
      label: 'db-01',
      host: '10.0.0.2',
      username: 'root',
      tags: ['Production'],
    ));

    await _pump(tester, hosts);

    expect(find.text('web-01'), findsOneWidget);
    expect(find.text('db-01'), findsOneWidget);
    expect(find.text('PRODUCTION'), findsOneWidget);
  });

  testWidgets('FAB is present', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.byType(MobileFab), findsOneWidget);
  });
}
