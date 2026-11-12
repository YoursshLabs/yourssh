import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/app_launcher.dart';

void main() {
  group('isExecutableExtension', () {
    test('windows blocks executable/script types, case-insensitively', () {
      for (final n in [
        'a.exe', 'a.BAT', 'a.cmd', 'a.Lnk', 'a.hta', 'a.ps1', 'a.url',
        'a.appref-ms', 'a.js', 'a.msi', 'a.scr', 'a.reg', 'a.cpl',
      ]) {
        expect(isExecutableExtension(n, 'windows'), isTrue, reason: n);
      }
    });

    test('windows ignores trailing dots/spaces that the OS strips', () {
      expect(isExecutableExtension('a.exe.', 'windows'), isTrue);
      expect(isExecutableExtension('a.bat ', 'windows'), isTrue);
    });

    test('macos and linux lists', () {
      for (final n in ['a.app', 'a.command', 'a.pkg', 'a.terminal', 'a.jar']) {
        expect(isExecutableExtension(n, 'macos'), isTrue, reason: n);
      }
      for (final n in ['a.desktop', 'a.sh', 'a.run', 'a.bin', 'a.AppImage']) {
        expect(isExecutableExtension(n, 'linux'), isTrue, reason: n);
      }
    });

    test('plain documents and extensionless names are allowed', () {
      for (final p in ['windows', 'macos', 'linux']) {
        expect(isExecutableExtension('notes.txt', p), isFalse);
        expect(isExecutableExtension('report.pdf', p), isFalse);
        expect(isExecutableExtension('Makefile', p), isFalse);
        expect(isExecutableExtension('.bashrc', p), isFalse);
      }
    });

    test('lists are per-platform', () {
      expect(isExecutableExtension('a.desktop', 'windows'), isFalse);
      expect(isExecutableExtension('a.exe', 'linux'), isFalse);
      expect(isExecutableExtension('a.command', 'linux'), isFalse);
    });
  });

  group('buildAppLaunch', () {
    test('windows spawns the app directly, never through a shell', () {
      final spec = buildAppLaunch(
          platform: 'windows', filePath: r'C:\t\x&calc&.txt', appPath: r'C:\a.exe');
      expect(spec.executable, r'C:\a.exe');
      expect(spec.arguments, [r'C:\t\x&calc&.txt']);
      expect(spec.runInShell, isFalse);
    });

    test('macos uses open -a', () {
      final spec = buildAppLaunch(
          platform: 'macos', filePath: '/t/f', appPath: '/Applications/X.app');
      expect(spec.executable, 'open');
      expect(spec.arguments, ['-a', '/Applications/X.app', '/t/f']);
      expect(spec.runInShell, isFalse);
    });

    test('linux spawns the app directly', () {
      final spec =
          buildAppLaunch(platform: 'linux', filePath: '/t/f', appPath: '/usr/bin/x');
      expect(spec.executable, '/usr/bin/x');
      expect(spec.arguments, ['/t/f']);
    });
  });
}
