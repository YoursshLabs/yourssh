import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/import_panel.dart';

void main() {
  group('parseSshConfig', () {
    test('parses a single Host block', () {
      const input = '''
Host myserver
    HostName 192.168.1.10
    User ubuntu
    Port 2222
''';
      final hosts = parseSshConfig(input);
      expect(hosts.length, 1);
      expect(hosts[0].label, 'myserver');
      expect(hosts[0].host, '192.168.1.10');
      expect(hosts[0].username, 'ubuntu');
      expect(hosts[0].port, 2222);
    });

    test('defaults User to root and Port to 22 when missing', () {
      const input = 'Host bare\n    HostName 10.0.0.1\n';
      final hosts = parseSshConfig(input);
      expect(hosts[0].username, 'root');
      expect(hosts[0].port, 22);
    });

    test('skips Host * wildcard blocks', () {
      const input = '''
Host *
    ServerAliveInterval 60

Host real
    HostName 1.2.3.4
    User admin
''';
      final hosts = parseSshConfig(input);
      expect(hosts.length, 1);
      expect(hosts[0].label, 'real');
    });

    test('parses multiple Host blocks', () {
      const input = '''
Host prod
    HostName prod.example.com
    User deploy

Host staging
    HostName staging.example.com
    User deploy
    Port 2022
''';
      final hosts = parseSshConfig(input);
      expect(hosts.length, 2);
      expect(hosts[1].label, 'staging');
      expect(hosts[1].port, 2022);
    });

    test('returns empty list for empty string', () {
      expect(parseSshConfig(''), isEmpty);
    });
  });

  group('parseJsonHosts', () {
    test('parses a JSON array of hosts', () {
      const input = '''[
  {"label":"Web","host":"web.example.com","port":22,"username":"admin",
   "authType":"password","group":"prod","tags":[]}
]''';
      final hosts = parseJsonHosts(input);
      expect(hosts.length, 1);
      expect(hosts[0].label, 'Web');
      expect(hosts[0].host, 'web.example.com');
      expect(hosts[0].group, 'prod');
    });

    test('assigns new ids (does not reuse imported ids)', () {
      const input = '''[
  {"id":"old-id-123","label":"A","host":"1.2.3.4","port":22,
   "username":"root","authType":"password","group":"","tags":[]}
]''';
      final hosts = parseJsonHosts(input);
      expect(hosts[0].id, isNot('old-id-123'));
    });

    test('returns empty list for invalid JSON', () {
      expect(parseJsonHosts('not json at all'), isEmpty);
    });

    test('returns empty list for empty input', () {
      expect(parseJsonHosts(''), isEmpty);
    });
  });

  group('detectAndParse', () {
    test('detects ssh config when input starts with "Host "', () {
      const input = 'Host server\n    HostName 1.2.3.4\n    User root\n';
      final result = detectAndParse(input);
      expect(result, isNotEmpty);
      expect(result[0].label, 'server');
    });

    test('detects JSON when input starts with [', () {
      const input =
          '[{"label":"X","host":"x.com","port":22,"username":"u","authType":"password","group":"","tags":[]}]';
      final result = detectAndParse(input);
      expect(result, isNotEmpty);
      expect(result[0].label, 'X');
    });

    test('returns empty list for unrecognized format', () {
      expect(detectAndParse('random garbage'), isEmpty);
    });

    test('detects CSV when first line contains commas', () {
      const csv = 'host,label\nserver.com,My Server';
      final result = detectAndParse(csv);
      expect(result.length, 1);
      expect(result[0].host, 'server.com');
    });
  });

  group('parseCsvHosts', () {
    test('basic row — parses host, label, username, port', () {
      const csv = 'label,host,port,username\nMy Server,1.2.3.4,2222,deploy';
      final result = parseCsvHosts(csv);
      expect(result.warnings, isEmpty);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'My Server');
      expect(result.hosts[0].host, '1.2.3.4');
      expect(result.hosts[0].port, 2222);
      expect(result.hosts[0].username, 'deploy');
    });

    test('missing optional fields — defaults: port=22, auth=password, label=host', () {
      const csv = 'host\n10.0.0.1';
      final result = parseCsvHosts(csv);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, '10.0.0.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].authType, AuthType.password);
      expect(result.hosts[0].username, '');
      expect(result.hosts[0].group, '');
      expect(result.hosts[0].tags, isEmpty);
    });

    test('quoted value with comma inside', () {
      const csv = 'label,host\n"New York, NY",nyc.example.com';
      final result = parseCsvHosts(csv);
      expect(result.hosts[0].label, 'New York, NY');
    });

    test('tags parsed as semicolon-separated list', () {
      const csv = 'host,tags\nserver.com,web;db';
      final result = parseCsvHosts(csv);
      expect(result.hosts[0].tags, ['web', 'db']);
    });

    test('auth_type: key→privateKey, agent→agent, password→password, unknown→password', () {
      const csv = 'host,auth_type\na.com,key\nb.com,agent\nc.com,password\nd.com,kerberos';
      final result = parseCsvHosts(csv);
      expect(result.hosts[0].authType, AuthType.privateKey);
      expect(result.hosts[1].authType, AuthType.agent);
      expect(result.hosts[2].authType, AuthType.password);
      expect(result.hosts[3].authType, AuthType.password);
    });

    test('empty rows are silently skipped — no warnings', () {
      const csv = 'host\n1.2.3.4\n\n5.6.7.8';
      final result = parseCsvHosts(csv);
      expect(result.hosts.length, 2);
      expect(result.warnings, isEmpty);
    });

    test('missing host column — throws FormatException', () {
      const csv = 'label,port\nMy Server,22';
      expect(() => parseCsvHosts(csv), throwsA(isA<FormatException>()));
    });

    test('empty host cell — row skipped with warning', () {
      const csv = 'host,label\n,Empty Host';
      final result = parseCsvHosts(csv);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains('missing host'));
    });

    test('invalid port — row skipped with warning', () {
      const csv = 'host,port\nserver.com,99999';
      final result = parseCsvHosts(csv);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains("invalid port '99999'"));
    });

    test('unknown auth_type defaults to password — no warning', () {
      const csv = 'host,auth_type\nserver.com,kerberos';
      final result = parseCsvHosts(csv);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].authType, AuthType.password);
      expect(result.warnings, isEmpty);
    });
  });
}
