import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Future<void> _pump(WidgetTester tester) async {
  final storage = StorageService();
  final ssh = SshService(storage);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => HostProvider(storage)),
      ChangeNotifierProvider(create: (_) => KeyProvider()),
      ChangeNotifierProvider(create: (_) => KnownHostsProvider(storage)),
      ChangeNotifierProvider(
          create: (_) => SessionProvider(ssh, TabMetadataService())),
    ],
    child: const MaterialApp(home: MobileHomeShell()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows four destinations; Hosts first', (tester) async {
    await _pump(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('No hosts'), findsOneWidget); // Hosts screen body
  });

  testWidgets('SFTP tab prompts to connect when no session', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('SFTP').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Connect a host'), findsOneWidget);
  });
}
