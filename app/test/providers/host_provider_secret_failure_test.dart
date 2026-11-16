import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

/// In-memory store whose savePassword can be told to fail on the Nth call.
class _FakeStorage extends StorageService {
  final secrets = <String, String>{};
  int saves = 0;
  int? failOnSave;

  @override
  Future<void> savePassword(String hostId, String password) async {
    saves++;
    if (failOnSave == saves) {
      throw SecretStoreException('pw_$hostId', 'keychain locked');
    }
    secrets[hostId] = password;
  }

  @override
  Future<String?> loadPassword(String hostId) async => secrets[hostId];

  @override
  Future<void> deletePassword(String hostId) async => secrets.remove(hostId);

  @override
  Future<void> deleteHostSecrets(String hostId) async =>
      secrets.remove(hostId);
}

Host _h(String id) =>
    Host(id: id, label: id, host: '1.2.3.4', port: 22, username: 'u');

void main() {
  late _FakeStorage storage;
  late HostProvider provider;
  late int mutations;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = _FakeStorage();
    provider = HostProvider(storage);
    mutations = 0;
    provider.onMutation = () async => mutations++;
    await Future<void>.delayed(Duration.zero);
  });

  test('addHost: failed secret write leaves no host and no mutation', () async {
    storage.failOnSave = 1;
    await expectLater(provider.addHost(_h('a'), password: 'pw'),
        throwsA(isA<SecretStoreException>()));
    expect(provider.allHosts, isEmpty);
    expect((await storage.loadHosts()), isEmpty);
    expect(mutations, 0);

    // Save again (keychain recovered): exactly one host, no duplicate.
    storage.failOnSave = null;
    await provider.addHost(_h('a'), password: 'pw');
    expect(provider.allHosts.length, 1);
    expect(storage.secrets['a'], 'pw');
  });

  test('updateHost: failed secret write keeps the old host', () async {
    await provider.addHost(_h('a'), password: 'old');
    storage.failOnSave = storage.saves + 1;
    final edited = _h('a').copyWith(label: 'renamed');
    await expectLater(provider.updateHost(edited, password: 'new'),
        throwsA(isA<SecretStoreException>()));
    expect(provider.allHosts.single.label, 'a');
    expect((await storage.loadHosts()).single.label, 'a');
    expect(storage.secrets['a'], 'old');
  });

  test('replaceAll: failure on the 2nd password changes nothing', () async {
    await provider.addHost(_h('a'), password: 'oldA');
    await provider.addHost(_h('b'), password: 'oldB');
    mutations = 0;
    storage.failOnSave = storage.saves + 2;
    await expectLater(
      provider.replaceAll(
        [_h('a'), _h('b'), _h('c')],
        {'pw_a': 'newA', 'pw_b': 'newB', 'pw_c': 'newC'},
      ),
      throwsA(isA<SecretStoreException>()),
    );
    expect(provider.allHosts.map((h) => h.id), ['a', 'b']);
    expect((await storage.loadHosts()).map((h) => h.id), ['a', 'b']);
    expect(storage.secrets, {'a': 'oldA', 'b': 'oldB'});
  });
}
