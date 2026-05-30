import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/ssh_service.dart';

void main() {
  group('SshService.parseOsFromUname', () {
    test('Linux output returns linux', () {
      expect(SshService.parseOsFromUname('Linux'), 'linux');
    });

    test('Darwin output returns macos', () {
      expect(SshService.parseOsFromUname('Darwin'), 'macos');
    });

    test('Windows_NT output returns windows', () {
      expect(SshService.parseOsFromUname('Windows_NT'), 'windows');
    });

    test('MINGW output returns windows', () {
      expect(SshService.parseOsFromUname('MINGW64_NT-10.0'), 'windows');
    });

    test('CYGWIN output returns windows', () {
      expect(SshService.parseOsFromUname('CYGWIN_NT-10.0'), 'windows');
    });

    test('empty output returns null', () {
      expect(SshService.parseOsFromUname(''), isNull);
    });

    test('unknown output returns null', () {
      expect(SshService.parseOsFromUname('FreeBSD'), isNull);
    });
  });
}
