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
}
