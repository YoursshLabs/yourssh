import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Copy SSH URL formatting', () {
    test('formats standard port correctly', () {
      final host = Host(label: 'Test', host: 'example.com', port: 22, username: 'admin');
      final url = 'ssh://${host.username}@${host.host}:${host.port}';
      expect(url, 'ssh://admin@example.com:22');
    });

    test('formats non-standard port correctly', () {
      final host = Host(label: 'Test', host: '10.0.0.1', port: 2222, username: 'root');
      final url = 'ssh://${host.username}@${host.host}:${host.port}';
      expect(url, 'ssh://root@10.0.0.1:2222');
    });
  });

  group('Duplicate host', () {
    test('copy has different id', () {
      final original = Host(label: 'Prod', host: '1.2.3.4', port: 22, username: 'root');
      final copy = Host(
        label: '${original.label} (copy)',
        host: original.host,
        port: original.port,
        username: original.username,
        authType: original.authType,
        keyId: original.keyId,
        group: original.group,
      );
      expect(copy.id, isNot(original.id));
      expect(copy.label, 'Prod (copy)');
      expect(copy.host, original.host);
      expect(copy.group, original.group);
    });
  });
}
