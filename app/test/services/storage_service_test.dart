import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  /// Backs the FlutterSecureStorage mock with an in-memory map so tests can
  /// observe what was written / read / deleted.
  late Map<String, String> secureStore;
  late int writeCallCount;
  late bool secureFailsNextWrite;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore = {};
    writeCallCount = 0;
    secureFailsNextWrite = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          writeCallCount++;
          if (secureFailsNextWrite) {
            secureFailsNextWrite = false;
            throw PlatformException(code: 'kSecMissingEntitlement');
          }
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('StorageService passwords', () {
    test('savePassword writes to secure storage', () async {
      final svc = StorageService();
      await svc.savePassword('host-1', 's3cret');

      expect(secureStore['pw_host-1'], 's3cret');
      expect(writeCallCount, 1);
    });

    test('savePassword purges prior plaintext prefs fallback on success',
        () async {
      // Pretend a prior version left a plaintext entry in prefs.
      SharedPreferences.setMockInitialValues({'pw_host-1': 'old-plaintext'});

      final svc = StorageService();
      await svc.savePassword('host-1', 'new-secret');

      // Secure write succeeded → prefs copy must be purged.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pw_host-1'), isNull,
          reason: 'plaintext fallback should be cleaned up on secure success');
      expect(secureStore['pw_host-1'], 'new-secret');
    });

    test('savePassword falls back to prefs when secure storage throws',
        () async {
      secureFailsNextWrite = true;
      final svc = StorageService();
      await svc.savePassword('host-1', 'fallback-secret');

      // Secure write threw → must fall back to plaintext rather than lose data.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pw_host-1'), 'fallback-secret');
      expect(secureStore.containsKey('pw_host-1'), isFalse);
    });

    test('loadPassword prefers secure storage over prefs', () async {
      SharedPreferences.setMockInitialValues({'pw_host-1': 'from-prefs'});
      secureStore['pw_host-1'] = 'from-secure';

      final svc = StorageService();
      expect(await svc.loadPassword('host-1'), 'from-secure');
    });

    test('loadPassword falls back to prefs when secure storage is empty',
        () async {
      SharedPreferences.setMockInitialValues({'pw_host-1': 'from-prefs'});

      final svc = StorageService();
      expect(await svc.loadPassword('host-1'), 'from-prefs');
    });

    test('deletePassword removes from both stores', () async {
      SharedPreferences.setMockInitialValues({'pw_host-1': 'leftover'});
      secureStore['pw_host-1'] = 's3cret';

      final svc = StorageService();
      await svc.deletePassword('host-1');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pw_host-1'), isNull);
      expect(secureStore.containsKey('pw_host-1'), isFalse);
    });
  });

  group('StorageService generic secrets', () {
    test('saveGenericSecret + loadGenericSecret round-trip', () async {
      final svc = StorageService();
      await svc.saveGenericSecret('sync_passphrase', 'correct horse');
      expect(await svc.loadGenericSecret('sync_passphrase'), 'correct horse');
    });

    test('deleteGenericSecret clears both stores', () async {
      SharedPreferences.setMockInitialValues({'sync_passphrase': 'leftover'});
      secureStore['sync_passphrase'] = 'value';

      final svc = StorageService();
      await svc.deleteGenericSecret('sync_passphrase');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_passphrase'), isNull);
      expect(secureStore.containsKey('sync_passphrase'), isFalse);
    });
  });

  group('sudo password secret', () {
    test('save / load / delete round-trip under sudopw_ key', () async {
      final svc = StorageService();

      await svc.saveSudoPassword('h1', 's3cret');
      expect(secureStore['sudopw_h1'], 's3cret');
      expect(await svc.loadSudoPassword('h1'), 's3cret');

      await svc.deleteSudoPassword('h1');
      expect(secureStore.containsKey('sudopw_h1'), isFalse);
      expect(await svc.loadSudoPassword('h1'), isNull);
    });
  });
}
