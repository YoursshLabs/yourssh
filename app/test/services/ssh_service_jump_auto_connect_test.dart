import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

/// connect() is overridden to record its arguments and bail out before any
/// network IO — ensureClient's resolution logic is what's under test.
class _Sentinel implements Exception {}

class _RecordingSshService extends SshService {
  _RecordingSshService(super.storage);

  Host? capturedJumpHost;
  SshKeyEntry? capturedJumpKeyEntry;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    capturedJumpHost = jumpHost;
    capturedJumpKeyEntry = jumpKeyEntry;
    throw _Sentinel();
  }
}

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

  _RecordingSshService makeService() {
    final svc = _RecordingSshService(StorageService());
    svc.defaultHostKeyVerifier = (host, port, keyType, fp) async => true;
    return svc;
  }

  test('ensureClient resolves jumpHostId via defaultJumpHostLookup', () async {
    final svc = makeService();
    final bastion = Host(
        id: 'jump-id',
        label: 'bastion',
        host: '10.0.0.1',
        username: 'jump',
        keyId: 'k1');
    final keyEntry = SshKeyEntry(
        id: 'k1',
        label: 'key',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'pub',
        privateKeyPath: '/tmp/k');
    svc.defaultJumpHostLookup = (id) => id == 'jump-id' ? bastion : null;
    svc.defaultKeyLookup = (id) => id == 'k1' ? keyEntry : null;

    final target = Host(
        label: 'behind-bastion',
        host: '10.0.0.2',
        username: 'app',
        jumpHostId: 'jump-id');

    await expectLater(svc.ensureClient(target), throwsA(isA<_Sentinel>()));
    expect(svc.capturedJumpHost?.id, 'jump-id');
    expect(svc.capturedJumpKeyEntry?.id, 'k1');
  });

  test('ensureClient passes no jumpHost for a direct host', () async {
    final svc = makeService();
    svc.defaultJumpHostLookup = (_) => fail('must not be called');

    final target = Host(label: 'direct', host: '10.0.0.3', username: 'app');

    await expectLater(svc.ensureClient(target), throwsA(isA<_Sentinel>()));
    expect(svc.capturedJumpHost, isNull);
    expect(svc.capturedJumpKeyEntry, isNull);
  });
}
