import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host', () {
    test('toJson/fromJson round-trips all fields', () {
      final h = Host(
        label: 'Test Server',
        host: '192.168.1.100',
        port: 2222,
        username: 'admin',
        authType: AuthType.password,
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.id, h.id);
      expect(decoded.label, 'Test Server');
      expect(decoded.host, '192.168.1.100');
      expect(decoded.port, 2222);
      expect(decoded.username, 'admin');
      expect(decoded.authType, AuthType.password);
    });

    test('certificate AuthType round-trips through JSON', () {
      final h = Host(
        label: 'Test',
        host: '1.2.3.4',
        username: 'user',
        authType: AuthType.certificate,
        keyId: 'key-1',
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.authType, AuthType.certificate);
      expect(decoded.keyId, 'key-1');
    });

    test('unknown authType throws ArgumentError', () {
      final json = {
        'id': 'x',
        'label': 'x',
        'host': 'x',
        'port': 22,
        'username': 'x',
        'authType': 'nonexistent',
        'group': '',
        'tags': [],
        'createdAt': DateTime.now().toIso8601String(),
      };
      // byName throws ArgumentError on unknown values
      expect(() => Host.fromJson(json), throwsArgumentError);
    });
  });
}
