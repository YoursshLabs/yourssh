import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('HostProvider pinnedGroups', () {
    late HostProvider provider;

    setUp(() {
      provider = HostProvider(StorageService());
    });

    tearDown(() => provider.dispose());

    test('starts with empty pinnedGroups', () async {
      await Future.delayed(Duration.zero); // allow _load to complete
      expect(provider.pinnedGroups, isEmpty);
    });

    test('addGroup appends to pinnedGroups', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Production');
      expect(provider.pinnedGroups, ['Production']);
    });

    test('addGroup ignores duplicates (case-insensitive)', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Production');
      await provider.addGroup('production');
      expect(provider.pinnedGroups.length, 1);
    });

    test('removeGroup removes the group', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Staging');
      await provider.removeGroup('Staging');
      expect(provider.pinnedGroups, isEmpty);
    });

    test('pinnedGroups persists across provider instances', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Saved');
      final provider2 = HostProvider(StorageService());
      await Future.delayed(Duration.zero);
      expect(provider2.pinnedGroups, ['Saved']);
      provider2.dispose();
    });
  });
}
