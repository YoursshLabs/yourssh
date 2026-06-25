import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_sessions_screen.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty state with no sessions', (tester) async {
    final sp =
        SessionProvider(SshService(StorageService()), TabMetadataService());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: sp,
        child: const MobileSessionsScreen(),
      ),
    ));
    expect(find.textContaining('No active sessions'), findsOneWidget);
  });
}
