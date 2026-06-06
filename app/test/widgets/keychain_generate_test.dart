import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh/widgets/keychain_screen.dart';

class _FakeKeyGen extends KeyGenService {
  _FakeKeyGen({required this.sshKeygenAvailable});
  final bool sshKeygenAvailable;

  @override
  Future<bool> probeSshKeygen() async => sshKeygenAvailable;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, KeyGenService keyGen) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => KeyProvider())],
      child:
          MaterialApp(home: Scaffold(body: KeychainScreen(keyGen: keyGen))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('rsa/ecdsa options disabled when ssh-keygen is missing',
      (tester) async {
    await pump(tester, _FakeKeyGen(sshKeygenAvailable: false));
    // 'GENERATE' renders in both the top bar and the empty state.
    await tester.tap(find.text('GENERATE').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('require OpenSSH client'), findsOneWidget);
    // Tapping a disabled item must not change the selection.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RSA 4096').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    // Dismiss the menu if it is still open, then check the selection.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Ed25519 (recommended)'), findsOneWidget);
  });

  testWidgets('rsa/ecdsa enabled when ssh-keygen exists', (tester) async {
    await pump(tester, _FakeKeyGen(sshKeygenAvailable: true));
    await tester.tap(find.text('GENERATE').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('require OpenSSH client'), findsNothing);
  });
}
