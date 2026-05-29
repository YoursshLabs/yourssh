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
}
