import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('exec auto-connect throws StateError when defaultHostKeyVerifier is null',
      () async {
    // Pins the round-2 TOFU-bypass fix: if no verifier is wired, exec() (which
    // would otherwise silently connect with onVerifyHostKey: return true) must
    // refuse. Reverting the wiring in main.dart should fail this test.
    final svc = SshService(StorageService());
    final host =
        Host(label: 'unreachable', host: '127.0.0.1', port: 1, username: 'x');

    await expectLater(
      svc.exec(host, 'echo hi'),
      throwsA(isA<StateError>()),
    );
  });

  test('openSftp auto-connect throws StateError when defaultHostKeyVerifier is null',
      () async {
    final svc = SshService(StorageService());
    final host =
        Host(label: 'unreachable', host: '127.0.0.1', port: 1, username: 'x');

    await expectLater(
      svc.openSftp(host),
      throwsA(isA<StateError>()),
    );
  });

  test('connect with certificate auth throws eagerly when no key is linked',
      () async {
    // Pre-refactor (round 3) this silently fell through to empty identities
    // and let dartssh2 surface a generic auth failure. The new behaviour fails
    // fast with an actionable message — pin it so the lenient fall-through
    // doesn't sneak back in.
    final svc = SshService(StorageService());
    final host = Host(
      label: 'cert-no-key',
      host: '127.0.0.1',
      port: 1,
      username: 'x',
      authType: AuthType.certificate,
    );
    await expectLater(
      svc.connect(host),
      throwsA(predicate((e) =>
          e is Exception && e.toString().contains('No key linked for certificate auth'))),
    );
  });
}
