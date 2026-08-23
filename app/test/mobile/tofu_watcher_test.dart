import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/security/tofu_watcher.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a dialog on host-key mismatch and Trust accepts',
      (tester) async {
    final kh = KnownHostsProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: kh,
        child: const TofuWatcher(child: Scaffold(body: SizedBox())),
      ),
    ));

    final fp1 = Uint8List.fromList(List.filled(16, 1));
    final fp2 = Uint8List.fromList(List.filled(16, 2));
    await kh.verifyHostKey('h', 22, 'ssh-ed25519', fp1); // first-use trust
    final future = kh.verifyHostKey('h', 22, 'ssh-ed25519', fp2); // mismatch
    await tester.pumpAndSettle();

    expect(find.textContaining('host key'), findsOneWidget);
    await tester.tap(find.text('Trust'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });
}
