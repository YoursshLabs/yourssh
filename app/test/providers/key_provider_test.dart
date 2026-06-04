import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('KeyProvider certificate methods', () {
    test('setCertificate persists certificatePath on the key entry', () async {
      final provider = KeyProvider();
      await Future.delayed(Duration.zero);

      await provider.addKeyFromFile(_tmpKeyFile(), 'test-key');
      await Future.delayed(Duration.zero);

      final key = provider.keys.first;
      await provider.setCertificate(key.id, '/tmp/id_ed25519-cert.pub');

      expect(provider.keys.first.certificatePath, '/tmp/id_ed25519-cert.pub');
    });

    test('removeCertificate clears certificatePath', () async {
      final provider = KeyProvider();
      await Future.delayed(Duration.zero);

      await provider.addKeyFromFile(_tmpKeyFile(), 'test-key');
      await Future.delayed(Duration.zero);

      final key = provider.keys.first;
      await provider.setCertificate(key.id, '/tmp/id_ed25519-cert.pub');
      await provider.removeCertificate(key.id);

      expect(provider.keys.first.certificatePath, isNull);
    });
  });
}

String _tmpKeyFile() {
  final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
      'test_key_${DateTime.now().millisecondsSinceEpoch}');
  f.writeAsStringSync('placeholder');
  return f.path;
}
