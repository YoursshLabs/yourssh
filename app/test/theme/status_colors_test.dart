import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/health_monitor_service.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/session_tab.dart';
import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  (SessionProvider, HostProvider) makeProviders() {
    final storage = StorageService();
    final sessions = SessionProvider(SshService(storage), TabMetadataService());
    final hosts = HostProvider(storage);
    return (sessions, hosts);
  }

  // ignore: unused_element
  SshSession seedSession(SessionProvider sessions, Host host,
      ) {
    final session = SshSession(
        host: host, status: SessionStatus.connected);
    sessions.sessions.add(session);
    return session;
  }

  final host =
      Host(id: 'h1', label: 'prod', host: '1.2.3.4', port: 22, username: 'u');

  testWidgets('SessionTab health dot of a healthy connection is success',
      (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host);
    final health = HealthMonitorService(
        measure: (_) async => 10,
        connectedHostIds: () => const ['h1'],
        pollSeconds: () => 0);
    await health.tick();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: hosts),
        ChangeNotifierProvider(create: (_) => ShellIntegrationProvider()),
        ChangeNotifierProvider(
            create: (_) =>
                RecordingProvider(RecordingService(), getPath: () => '/tmp')),
        ChangeNotifierProvider.value(value: health),
      ],
      child: ysTestApp(Row(children: [
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
      ])),
    ));

    final dot = tester.widget<Container>(find.byKey(const Key('health-dot')));
    expect((dot.decoration as BoxDecoration).color, AppColors.success);
  });

  testWidgets('AppSnack.success uses the success colour', (tester) async {
    await tester.pumpWidget(ysTestApp(Builder(
      builder: (context) => TextButton(
        onPressed: () => AppSnack.success(context, 'Saved'),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.text('go'));
    await tester.pump();
    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.backgroundColor, AppColors.success);
  });
}
