import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('KeyProvider.ready completes after the load', () async {
    final p = KeyProvider();
    await p.ready;
  });

  test('KnownHostsProvider.ready tracks the latest load()', () async {
    final p = KnownHostsProvider(StorageService());
    final f = p.load();
    expect(identical(p.ready, f), isTrue);
    await p.ready;
  });
}
