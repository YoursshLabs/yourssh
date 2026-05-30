import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostProvider.updateDetectedOs', () {
    late HostProvider provider;
    late Host host;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = HostProvider(StorageService());
      host = Host(id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u');
      await provider.addHost(host);
    });

    test('sets detectedOs on matching host', () async {
      await provider.updateDetectedOs('h1', 'linux');
      expect(provider.allHosts.first.detectedOs, 'linux');
    });

    test('does not call onMutation', () async {
      var mutationCalled = false;
      provider.onMutation = () async => mutationCalled = true;
      await provider.updateDetectedOs('h1', 'linux');
      expect(mutationCalled, isFalse);
    });

    test('no-ops for unknown hostId', () async {
      await provider.updateDetectedOs('unknown', 'linux');
      expect(provider.allHosts.first.detectedOs, isNull);
    });
  });
}
