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
  late bool secureFailsAllWrites;
  /// Simulates a store that accepts the write but hands back something else,
  /// so migratePlaintextSecrets' read-back guard can be exercised.
  late bool secureCorruptsReads;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore = {};
    writeCallCount = 0;
    secureFailsNextWrite = false;
    secureFailsAllWrites = false;
    secureCorruptsReads = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          writeCallCount++;
          if (secureFailsAllWrites || secureFailsNextWrite) {
            secureFailsNextWrite = false;
            throw PlatformException(code: 'kSecMissingEntitlement');
          }
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          if (secureCorruptsReads) return null;
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

  group('macOS keychain selection (issue #91)', () {
    test('uses the legacy file keychain, not the data-protection one', () {
      // The data-protection keychain needs a keychain-access-group
      // entitlement, which an ad-hoc-signed build cannot carry: every
      // SecItemAdd returned -34018 and each secret silently landed in
      // SharedPreferences as readable text.
      expect(
        StorageService.macOsKeychainOptions.params['useDataProtectionKeyChain'],
        'false',
      );
      expect(StorageService.macOsKeychainOptions.params['accountName'],
          'yourssh');
    });
  });

  group('plaintext-secret carry-over (issue #91)', () {
    test('classifies which prefs keys hold secrets', () {
      expect(StorageService.isSecretPrefsKey('pw_host-1'), isTrue);
      expect(StorageService.isSecretPrefsKey('sudopw_host-1'), isTrue);
      expect(StorageService.isSecretPrefsKey('pp_key-1'), isTrue);
      expect(StorageService.isSecretPrefsKey('sync_passphrase'), isTrue);
      expect(StorageService.isSecretPrefsKey('yourssh.hosts'), isFalse);
      expect(StorageService.isSecretPrefsKey('auto_reconnect'), isFalse);
    });

    test('moves cleartext secrets into the secure store and clears prefs',
        () async {
      SharedPreferences.setMockInitialValues({
        'pw_host-1': 'hostpass',
        'sudopw_host-1': 'sudopass',
        'pp_key-1': 'keyphrase',
        'sync_passphrase': 'syncphrase',
        'yourssh.hosts': '[]', // not a secret — must be left alone
      });
      final svc = StorageService();

      expect(await svc.migratePlaintextSecrets(), 4);

      final prefs = await SharedPreferences.getInstance();
      for (final key in ['pw_host-1', 'sudopw_host-1', 'pp_key-1',
        'sync_passphrase']) {
        expect(prefs.getString(key), isNull, reason: '$key left in prefs');
      }
      expect(prefs.getString('yourssh.hosts'), '[]');
      expect(secureStore['pw_host-1'], 'hostpass');
      expect(secureStore['sudopw_host-1'], 'sudopass');
      expect(secureStore['pp_key-1'], 'keyphrase');
      expect(secureStore['sync_passphrase'], 'syncphrase');
      expect(svc.hasPlaintextSecrets, isFalse);
    });

    test('keeps the prefs copy when the secure write fails', () async {
      SharedPreferences.setMockInitialValues({'pw_host-1': 'hostpass'});
      secureFailsAllWrites = true;
      final svc = StorageService();

      expect(await svc.migratePlaintextSecrets(), 0);

      // Losing the only copy of a password would be worse than storing it
      // in cleartext, so the prefs entry stays put.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pw_host-1'), 'hostpass');
      expect(svc.plaintextSecretKeys, {'pw_host-1'});
    });

    test('keeps the prefs copy when the write cannot be read back', () async {
      SharedPreferences.setMockInitialValues({'pw_host-1': 'hostpass'});
      secureCorruptsReads = true;
      final svc = StorageService();

      expect(await svc.migratePlaintextSecrets(), 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pw_host-1'), 'hostpass');
      expect(svc.plaintextSecretKeys, {'pw_host-1'});
    });

    test('a value already in the secure store wins over the prefs copy',
        () async {
      // _loadSecret prefers the secure store, so the prefs entry is stale —
      // rewriting it would resurrect an old password.
      SharedPreferences.setMockInitialValues({'pw_host-1': 'stale'});
      secureStore['pw_host-1'] = 'current';
      final svc = StorageService();

      expect(await svc.migratePlaintextSecrets(), 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pw_host-1'), isNull);
      expect(secureStore['pw_host-1'], 'current');
    });

    test('a retry after the store recovers completes the move', () async {
      SharedPreferences.setMockInitialValues({'pw_host-1': 'hostpass'});
      secureFailsAllWrites = true;
      final svc = StorageService();
      await svc.migratePlaintextSecrets();
      expect(svc.hasPlaintextSecrets, isTrue);

      secureFailsAllWrites = false;
      expect(await svc.migratePlaintextSecrets(), 1);

      expect(svc.hasPlaintextSecrets, isFalse);
      expect(secureStore['pw_host-1'], 'hostpass');
    });
  });

  group('plaintext fallback is reported, not silent (issue #91)', () {
    test('a fallback write marks the key and notifies', () async {
      final reported = <String>[];
      final svc = StorageService()..onPlaintextFallback = (k, _) =>
          reported.add(k);
      var revisions = 0;
      svc.secretStorageRevision.addListener(() => revisions++);

      secureFailsNextWrite = true;
      await svc.savePassword('host-1', 'fallback-secret');

      expect(reported, ['pw_host-1']);
      expect(svc.plaintextSecretKeys, {'pw_host-1'});
      expect(svc.hasPlaintextSecrets, isTrue);
      expect(revisions, 1);
    });

    test('a later successful write clears the flag', () async {
      final svc = StorageService();
      secureFailsNextWrite = true;
      await svc.savePassword('host-1', 'fallback-secret');
      expect(svc.hasPlaintextSecrets, isTrue);

      await svc.savePassword('host-1', 'now-secure');

      expect(svc.hasPlaintextSecrets, isFalse);
      expect(secureStore['pw_host-1'], 'now-secure');
    });

    test('deleting the secret clears the flag', () async {
      final svc = StorageService();
      secureFailsNextWrite = true;
      await svc.savePassword('host-1', 'fallback-secret');

      await svc.deletePassword('host-1');

      expect(svc.hasPlaintextSecrets, isFalse);
    });

    test('the same failing key is only reported once', () async {
      var calls = 0;
      final svc = StorageService()..onPlaintextFallback = (_, _) => calls++;
      secureFailsAllWrites = true;

      await svc.savePassword('host-1', 'a');
      await svc.savePassword('host-1', 'b');

      expect(calls, 1);
    });
  });
}
