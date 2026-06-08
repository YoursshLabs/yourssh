import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/import_parsers.dart';

void main() {
  group('PuttyRegParser', () {
    const parser = PuttyRegParser();

    test('parses a single session', () {
      const input = '''Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\MyServer]
"HostName"="192.168.1.1"
"PortNumber"=dword:00000016
"UserName"="root"
''';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'MyServer');
      expect(result.hosts[0].host, '192.168.1.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].username, 'root');
      expect(result.warnings, isEmpty);
    });

    test('URL-decodes session name (%20 → space)', () {
      const input = '''Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\My%20Server]
"HostName"="10.0.0.1"
"PortNumber"=dword:00000016
"UserName"="admin"
''';
      final result = parser.parse(input);
      expect(result.hosts[0].label, 'My Server');
    });

    test('skips sections outside Sessions path', () {
      const input = '''Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\SshHostKeys]
"rsa2@22:1.2.3.4"="0x..."
''';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
    });

    test('session missing HostName produces a warning', () {
      const input = '''Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\BadSession]
"PortNumber"=dword:00000016
"UserName"="root"
''';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains('BadSession'));
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('parses multiple sessions with correct hex port conversion', () {
      const input = '''Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\ServerA]
"HostName"="1.1.1.1"
"PortNumber"=dword:00000016
"UserName"="admin"

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\ServerB]
"HostName"="2.2.2.2"
"PortNumber"=dword:0000006f
"UserName"="deploy"
''';
      final result = parser.parse(input);
      expect(result.hosts.length, 2);
      expect(result.hosts[0].label, 'ServerA');
      expect(result.hosts[1].label, 'ServerB');
      expect(result.hosts[1].port, 111);
    });
  });

  group('MobaXtermParser', () {
    const parser = MobaXtermParser();

    test('parses a single SSH session', () {
      const input = '[Bookmarks]\n'
          'SubRep=\n'
          'ImgNum=42\n'
          'SSH server1 (root) = 0  192.168.1.1  22  root  -1  -1  0\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'SSH server1 (root)');
      expect(result.hosts[0].host, '192.168.1.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].username, 'root');
      expect(result.warnings, isEmpty);
    });

    test('skips non-SSH sessions (type != 0)', () {
      const input = '[Bookmarks]\n'
          'Telnet server = 4  10.0.0.1  23  admin  -1\n'
          'SSH server = 0  10.0.0.2  22  root  -1\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].host, '10.0.0.2');
    });

    test('parses sessions across multiple [Bookmarks] sections', () {
      const input = '[Bookmarks]\n'
          'Server A = 0  1.1.1.1  22  admin  -1\n'
          '\n'
          '[Bookmarks_1]\n'
          'SubRep=DB\n'
          'Server B = 0  2.2.2.2  2222  deploy  -1\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 2);
      expect(result.hosts[1].port, 2222);
    });

    test('malformed SSH line (< 4 tokens in value) produces a warning', () {
      const input = '[Bookmarks]\nBad = 0  10.0.0.1\n';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains('Bad'));
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  group('SecureCrtParser', () {
    const parser = SecureCrtParser();

    test('parses a single session', () {
      const input = '''<?xml version="1.0" encoding="UTF-8"?>
<VanDyke>
  <key name="Sessions">
    <key name="MyServer">
      <value name="Hostname" type="string">192.168.1.1</value>
      <value name="Port" type="dword">22</value>
      <value name="Username" type="string">admin</value>
    </key>
  </key>
</VanDyke>
''';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'MyServer');
      expect(result.hosts[0].host, '192.168.1.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].username, 'admin');
      expect(result.warnings, isEmpty);
    });

    test('nested folder becomes group', () {
      const input = '''<?xml version="1.0" encoding="UTF-8"?>
<VanDyke>
  <key name="Sessions">
    <key name="Production">
      <key name="WebServer">
        <value name="Hostname" type="string">prod.example.com</value>
        <value name="Port" type="dword">22</value>
        <value name="Username" type="string">deploy</value>
      </key>
    </key>
  </key>
</VanDyke>
''';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'WebServer');
      expect(result.hosts[0].group, 'Production');
    });

    test('session missing Hostname is skipped silently', () {
      const input = '''<?xml version="1.0" encoding="UTF-8"?>
<VanDyke>
  <key name="Sessions">
    <key name="NoHost">
      <value name="Port" type="dword">22</value>
    </key>
  </key>
</VanDyke>
''';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('invalid XML returns a warning', () {
      final result = parser.parse('not xml at all');
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains('XML'));
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  group('AnsibleParser', () {
    const parser = AnsibleParser();

    test('parses bare hostname in a group', () {
      const input = '[webservers]\nweb1.example.com\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].host, 'web1.example.com');
      expect(result.hosts[0].label, 'web1.example.com');
      expect(result.hosts[0].group, 'webservers');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].username, 'root');
    });

    test('ansible_host overrides bare hostname', () {
      const input =
          '[db]\ndb-alias ansible_host=10.0.0.5 ansible_user=postgres ansible_port=5432\n';
      final result = parser.parse(input);
      expect(result.hosts[0].host, '10.0.0.5');
      expect(result.hosts[0].label, 'db-alias');
      expect(result.hosts[0].username, 'postgres');
      expect(result.hosts[0].port, 5432);
    });

    test('ansible_ssh_user is accepted as username alias', () {
      const input = '[servers]\nmyhost ansible_ssh_user=ubuntu\n';
      final result = parser.parse(input);
      expect(result.hosts[0].username, 'ubuntu');
    });

    test('skips :vars sections entirely', () {
      const input =
          '[webservers:vars]\nansible_user=deploy\n\n[webservers]\nweb1.example.com\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].host, 'web1.example.com');
    });

    test('skips :children sections entirely', () {
      const input = '[all:children]\nwebservers\ndatabases\n';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
    });

    test('skips comment lines', () {
      const input = '[servers]\n# this is a comment\nreal-server.com\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].host, 'real-server.com');
    });

    test('invalid ansible_port produces a warning and skips the host', () {
      const input = '[servers]\nbad-server ansible_port=notanumber\n';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains('ansible_port'));
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  group('WinScpParser', () {
    const parser = WinScpParser();

    test('parses a single session', () {
      const input = '[Sessions\\MyServer]\nHostName=192.168.1.1\nPortNumber=22\nUserName=admin\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'MyServer');
      expect(result.hosts[0].host, '192.168.1.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].username, 'admin');
      expect(result.warnings, isEmpty);
    });

    test('URL-decodes session name', () {
      const input =
          '[Sessions\\My%20Server]\nHostName=10.0.0.1\nPortNumber=22\nUserName=root\n';
      final result = parser.parse(input);
      expect(result.hosts[0].label, 'My Server');
    });

    test('skips root [Sessions\\] section', () {
      const input = '[Sessions\\]\nHostName=ignored.example.com\n';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
    });

    test('nested path: last component is label, parent components join as group', () {
      const input =
          '[Sessions\\Production\\WebServer]\nHostName=prod.example.com\nPortNumber=22\nUserName=deploy\n';
      final result = parser.parse(input);
      expect(result.hosts[0].label, 'WebServer');
      expect(result.hosts[0].group, 'Production');
    });

    test('session missing HostName is skipped silently', () {
      const input = '[Sessions\\NoHost]\nPortNumber=22\nUserName=admin\n';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  group('TermiusParser', () {
    const parser = TermiusParser();

    test('parses Termius JSON export format', () {
      const input = '{"hosts":['
          '{"label":"My Server","address":"192.168.1.1","port":22,'
          '"username":"admin","group":{"label":"Production"}}'
          ']}';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'My Server');
      expect(result.hosts[0].host, '192.168.1.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].username, 'admin');
      expect(result.hosts[0].group, 'Production');
      expect(result.warnings, isEmpty);
    });

    test('skips entries missing address', () {
      const input = '{"hosts":[{"label":"Bad","port":22,"username":"root"}]}';
      final result = parser.parse(input);
      expect(result.hosts, isEmpty);
    });

    test('host without group has empty group', () {
      const input =
          '{"hosts":[{"label":"X","address":"10.0.0.1","port":22,"username":"root"}]}';
      final result = parser.parse(input);
      expect(result.hosts[0].group, '');
    });

    test('falls back to YourSSH JSON array format when no hosts key', () {
      const input =
          '[{"label":"Web","host":"web.example.com","port":22,"username":"admin",'
          '"authType":"password","group":"","tags":[]}]';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'Web');
    });

    test('invalid JSON returns a warning', () {
      final result = parser.parse('not json');
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });

  group('SshUriParser', () {
    const parser = SshUriParser();

    test('parses ssh://user@host:port', () {
      const input = 'ssh://admin@192.168.1.1:2222';
      final result = parser.parse(input);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].host, '192.168.1.1');
      expect(result.hosts[0].username, 'admin');
      expect(result.hosts[0].port, 2222);
      expect(result.hosts[0].label, 'admin@192.168.1.1');
    });

    test('parses ssh://user@host without port — defaults to 22', () {
      const input = 'ssh://root@10.0.0.1';
      final result = parser.parse(input);
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].host, '10.0.0.1');
    });

    test('parses multiple URIs, one per line', () {
      const input = 'ssh://admin@server1.com:22\nssh://deploy@server2.com:2222\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 2);
      expect(result.hosts[0].host, 'server1.com');
      expect(result.hosts[1].host, 'server2.com');
    });

    test('skips non-URI lines silently — no warnings', () {
      const input =
          '# comment\nssh://user@host1.com\nnot-a-uri\nssh://user@host2.com\n';
      final result = parser.parse(input);
      expect(result.hosts.length, 2);
      expect(result.warnings, isEmpty);
    });

    test('empty input returns empty result', () {
      final result = parser.parse('');
      expect(result.hosts, isEmpty);
      expect(result.warnings, isEmpty);
    });
  });
}
