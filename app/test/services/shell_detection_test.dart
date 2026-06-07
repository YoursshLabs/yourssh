// app/test/services/shell_detection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/shell_detection.dart';

/// Encodes a string as UTF-16LE bytes — what wsl.exe emits on stdout.
List<int> utf16le(String s) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    out..add(u & 0xff)..add(u >> 8);
  }
  return out;
}

void main() {
  group('parseWslDistroList', () {
    test('decodes UTF-16LE with CRLF line ends, drops blanks', () {
      expect(parseWslDistroList(utf16le('Ubuntu\r\nDebian\r\n\r\n')),
          ['Ubuntu', 'Debian']);
    });

    test('strips a leading BOM', () {
      expect(parseWslDistroList([0xFF, 0xFE, ...utf16le('Ubuntu\r\n')]),
          ['Ubuntu']);
    });

    test('empty output yields no distros', () {
      expect(parseWslDistroList([]), isEmpty);
    });
  });

  group('parseEtcShells', () {
    test('drops comments, blanks and duplicates', () {
      expect(
        parseEtcShells('# /etc/shells\n/bin/bash\n\n/bin/zsh\n/bin/bash\n'),
        ['/bin/bash', '/bin/zsh'],
      );
    });
  });

  group('detectShells windows', () {
    test('always offers powershell+cmd, adds pwsh/git-bash/wsl when found',
        () async {
      final profiles = await detectShells(
        isWindows: true,
        env: {'ProgramFiles': r'C:\Program Files', 'PATH': ''},
        fileExists: (path) =>
            path == r'C:\Program Files\PowerShell\7\pwsh.exe' ||
            path == r'C:\Program Files\Git\bin\bash.exe',
        runRaw: (exe, args) async => utf16le('Ubuntu\r\n'),
      );
      expect(profiles.map((s) => s.id).toList(),
          ['powershell', 'cmd', 'pwsh', 'git-bash', 'wsl-Ubuntu']);
      final wsl = profiles.last;
      expect(wsl.executable, 'wsl.exe');
      expect(wsl.args, ['-d', 'Ubuntu']);
    });

    test('pwsh found via PATH scan', () async {
      final profiles = await detectShells(
        isWindows: true,
        env: {'PATH': r'C:\tools;C:\pwsh'},
        fileExists: (path) => path == r'C:\pwsh\pwsh.exe',
        runRaw: (_, _) async => null,
      );
      expect(profiles.map((s) => s.id), contains('pwsh'));
      expect(profiles.firstWhere((s) => s.id == 'pwsh').executable,
          r'C:\pwsh\pwsh.exe');
    });

    test('wsl failure yields no wsl profiles, detection continues', () async {
      final profiles = await detectShells(
        isWindows: true,
        env: {},
        fileExists: (_) => false,
        runRaw: (_, _) async => null,
      );
      expect(profiles.map((s) => s.id).toList(), ['powershell', 'cmd']);
    });
  });

  group('detectShells unix', () {
    test(r'$SHELL first, /etc/shells entries filtered to existing', () async {
      final profiles = await detectShells(
        isWindows: false,
        env: {'SHELL': '/bin/zsh'},
        fileExists: (path) => path != '/bin/missing',
        readFile: (_) => '/bin/bash\n/bin/missing\n/bin/zsh\n',
      );
      expect(profiles.map((s) => s.executable).toList(),
          ['/bin/zsh', '/bin/bash']);
      expect(profiles.first.id, 'etc-/bin/zsh');
      expect(profiles.first.name, 'zsh');
    });

    test(r'unreadable /etc/shells leaves only $SHELL', () async {
      final profiles = await detectShells(
        isWindows: false,
        env: {'SHELL': '/bin/zsh'},
        fileExists: (_) => true,
        readFile: (_) => null,
      );
      expect(profiles.map((s) => s.executable).toList(), ['/bin/zsh']);
    });
  });
}
