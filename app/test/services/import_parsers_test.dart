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
}
