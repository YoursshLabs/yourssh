import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock flutter_secure_storage channel
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> secureStorageData = {};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStorageData.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'read':
          final key = call.arguments['key'] as String;
          return secureStorageData[key];
        case 'write':
          final key = call.arguments['key'] as String;
          final value = call.arguments['value'] as String;
          secureStorageData[key] = value;
          return null;
        case 'delete':
          final key = call.arguments['key'] as String;
          secureStorageData.remove(key);
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStorageData);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SyncProvider', () {
    late SyncProvider provider;

    setUp(() {
      provider = SyncProvider();
    });

    tearDown(() => provider.dispose());

    test('initial state: disabled, idle, no error', () {
      expect(provider.enabled, false);
      expect(provider.status, SyncStatus.idle);
      expect(provider.error, isNull);
      expect(provider.lastSynced, isNull);
    });

    test('setEnabled notifies listeners', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.setEnabled(true);
      expect(notified, true);
      expect(provider.enabled, true);
    });

    test('setStatus notifies listeners', () {
      var count = 0;
      provider.addListener(() => count++);
      provider.setStatus(SyncStatus.syncing);
      provider.setStatus(SyncStatus.synced);
      expect(count, 2);
    });

    test('setError stores error message and sets error status', () {
      provider.setError('network failure');
      expect(provider.status, SyncStatus.error);
      expect(provider.error, 'network failure');
    });

    test('setStatus(synced) clears error and sets lastSynced', () {
      provider.setError('old error');
      provider.setStatus(SyncStatus.synced);
      expect(provider.error, isNull);
      expect(provider.lastSynced, isNotNull);
    });

    test('syncCodeDisplay formats syncId as XXXX-XXXX-XXXX', () {
      provider.syncId = 'X7KDM2PQ3RVA';
      expect(provider.syncCodeDisplay, 'X7KD-M2PQ-3RVA');
    });
  });

  group('SyncProvider keychain fallback', () {
    test('falls back to SharedPreferences syncId when secure storage throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'SecureStorageError', message: 'Keychain unavailable');
      });

      SharedPreferences.setMockInitialValues({'sync_id': 'PREFSSYNCID12'});

      final p = SyncProvider();
      final c = Completer<void>();
      p.addListener(() {
        if (p.syncId.isNotEmpty && !c.isCompleted) c.complete();
      });
      await c.future.timeout(const Duration(seconds: 2));

      expect(p.syncId, 'PREFSSYNCID12');
      p.dispose();
    });

    test('generates and stores new syncId in prefs when keychain throws and prefs empty', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'SecureStorageError', message: 'Keychain unavailable');
      });

      SharedPreferences.setMockInitialValues({});

      final p = SyncProvider();
      final c = Completer<void>();
      p.addListener(() {
        if (p.syncId.isNotEmpty && !c.isCompleted) c.complete();
      });
      await c.future.timeout(const Duration(seconds: 2));

      expect(p.syncId.length, 12);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_id'), p.syncId);
      p.dispose();
    });
  });
}
