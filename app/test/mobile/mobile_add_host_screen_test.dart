import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/mobile/screens/mobile_add_host_screen.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saving creates a host in the provider', (tester) async {
    final hosts = HostProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: hosts),
          ChangeNotifierProvider(create: (_) => KeyProvider()),
        ],
        child: const MobileAddHostScreen(),
      ),
    ));

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
}
