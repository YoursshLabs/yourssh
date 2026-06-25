import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_sftp_screen.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows connect prompt with no SSH session', (tester) async {
    final storage = StorageService();
    final ssh = SshService(storage);
    final sp = SessionProvider(ssh, TabMetadataService());
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: sp),
          Provider<SshService>.value(value: ssh),
        ],
        child: const MobileSftpScreen(),
      ),
    ));
    expect(find.textContaining('Connect a host'), findsOneWidget);
  });
}
