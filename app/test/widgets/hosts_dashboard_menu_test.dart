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
        tags: List<String>.from(original.tags),
      );
      expect(copy.id, isNot(original.id));
      expect(copy.label, 'Prod (copy)');
      expect(copy.host, original.host);
      expect(copy.group, original.group);
      expect(copy.tags, original.tags);
    });

    test('copy preserves tags', () {
      final original = Host(label: 'Prod', host: '1.2.3.4', port: 22, username: 'root', tags: ['prod', 'aws']);
      final copy = Host(
        label: '${original.label} (copy)',
        host: original.host,
        port: original.port,
        username: original.username,
        authType: original.authType,
        keyId: original.keyId,
        group: original.group,
        tags: List<String>.from(original.tags),
      );
      expect(copy.tags, ['prod', 'aws']);
    });
  });

  group('Export formats', () {
    late Host host;

    setUp(() {
      host = Host(
        label: 'My Server',
        host: '192.168.1.10',
        port: 2222,
        username: 'deploy',
        group: 'prod',
      );
    });

    test('ssh/config format', () {
      final output = 'Host ${host.label}\n'
          '    HostName ${host.host}\n'
          '    User ${host.username}\n'
          '    Port ${host.port}';
      expect(output, contains('Host My Server'));
      expect(output, contains('HostName 192.168.1.10'));
      expect(output, contains('User deploy'));
      expect(output, contains('Port 2222'));
    });

    test('json export excludes id and createdAt', () {
      final json = {
        'label': host.label,
        'host': host.host,
        'port': host.port,
        'username': host.username,
        'authType': host.authType.name,
        'group': host.group,
        'tags': host.tags,
      };
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('createdAt'), isFalse);
      expect(json['label'], 'My Server');
    });
  });

  group('Move to Group — group list', () {
    test('derives distinct non-empty groups from host list', () {
      final hosts = [
        Host(label: 'A', host: 'a.com', port: 22, username: 'u', group: 'production'),
        Host(label: 'B', host: 'b.com', port: 22, username: 'u', group: 'staging'),
        Host(label: 'C', host: 'c.com', port: 22, username: 'u', group: 'production'),
        Host(label: 'D', host: 'd.com', port: 22, username: 'u', group: ''),
      ];
      final groups = hosts
          .map((h) => h.group)
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      expect(groups, ['production', 'staging']);
    });

    test('returns empty list when all hosts have no group', () {
      final hosts = [
        Host(label: 'A', host: 'a.com', port: 22, username: 'u'),
      ];
      final groups = hosts
          .map((h) => h.group)
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList();
      expect(groups, isEmpty);
    });
  });
}
