import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

/// Locks in empty-password SSH support: a blank password is never persisted
/// (so `loadPassword` stays null) and the connect path sends '' to the server
/// via `onPasswordRequest: () => password ?? ''` in SshService.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late HostProvider provider;
  final host =
      Host(id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    provider = HostProvider(storage);
  });

  test('addHost with empty password saves nothing', () async {
    await provider.addHost(host, password: '');
    expect(await storage.loadPassword('h1'), isNull);
  });

  test('addHost with null password saves nothing', () async {
    await provider.addHost(host);
    expect(await storage.loadPassword('h1'), isNull);
  });

  test('addHost with a real password persists it', () async {
    await provider.addHost(host, password: 's3cret');
    expect(await storage.loadPassword('h1'), 's3cret');
  });

  test('updateHost with empty password keeps the stored one', () async {
    await provider.addHost(host, password: 's3cret');
    await provider.updateHost(host, password: '');
    expect(await storage.loadPassword('h1'), 's3cret');
  });

  test('deleteHost purges every per-host secret, secure store and prefs',
      () async {
    final secure = <String, String>{};
    const ch = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
      final a = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          secure[a['key'] as String] = a['value'] as String;
          return null;
        case 'read':
          return secure[a['key'] as String];
        case 'delete':
          secure.remove(a['key'] as String);
          return null;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null));

    await provider.addHost(host, password: 'a');
    await storage.saveSudoPassword('h1', 'b');
    await storage.saveGenericSecret('proxy_pw_h1', 'c');
    // Stale plaintext fallback copies in prefs.
    SharedPreferences.setMockInitialValues({
      'pw_h1': 'a',
      'sudopw_h1': 'b',
      'proxy_pw_h1': 'c',
    });
    await provider.deleteHost('h1');

    for (final k in ['pw_h1', 'sudopw_h1', 'proxy_pw_h1']) {
      expect(secure.containsKey(k), isFalse, reason: '$k in secure store');
      expect(await storage.loadGenericSecret(k), isNull, reason: k);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.endsWith('_h1')), isEmpty);
  });
}
