import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_sftp_screen.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

// Updated after Task 13 redesign: MobileSftpScreen is now contextual and
// requires a [Host]. The full smoke-test suite lives in
// test/mobile/screens/sftp_screen_test.dart.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows empty folder message with empty listing', (tester) async {
    final storage = StorageService();
    final ssh = SshService(storage);
    final transfer = SftpTransferService(ssh);
    final host = Host(
      id: 'h1',
      label: 'web-01',
      host: '10.0.0.1',
      port: 22,
      username: 'deploy',
    );

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<SshService>.value(value: ssh),
          Provider<SftpTransferService>.value(value: transfer),
        ],
        child: MobileSftpScreen(
          host: host,
          lister: (_) async => [],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Empty'), findsOneWidget);
  });
}
