import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/os_detection.dart';

void main() {
  group('parseOsReleaseId', () {
    test('unquoted ID', () {
      const content = 'NAME="Ubuntu"\nID=ubuntu\nVERSION_ID="24.04"\n';
      expect(parseOsReleaseId(content), 'ubuntu');
    });

    test('double-quoted ID', () {
      const content = 'NAME="Rocky Linux"\nID="rocky"\nID_LIKE="rhel centos fedora"\n';
      expect(parseOsReleaseId(content), 'rocky');
    });

    test('single-quoted ID', () {
      expect(parseOsReleaseId("ID='alpine'\n"), 'alpine');
    });

    test('ignores ID_LIKE and VERSION_ID', () {
      const content = 'VERSION_ID="9.3"\nID_LIKE="rhel fedora"\nID=almalinux\n';
      expect(parseOsReleaseId(content), 'almalinux');
    });

    test('missing ID returns null', () {
      expect(parseOsReleaseId('NAME="Something"\nVERSION_ID="1"\n'), isNull);
    });

    test('empty content returns null', () {
      expect(parseOsReleaseId(''), isNull);
    });

    test('uppercase value is lowercased', () {
      expect(parseOsReleaseId('ID=Ubuntu\n'), 'ubuntu');
    });
  });

  group('normalizeDistroId', () {
    test('known ids pass through', () {
      for (final id in kOsIconKeys) {
        expect(normalizeDistroId(id), id);
      }
    });

    test('aliases map to icon keys', () {
      expect(normalizeDistroId('amzn'), 'amazon');
      expect(normalizeDistroId('almalinux'), 'alma');
      expect(normalizeDistroId('rhel'), 'redhat');
      expect(normalizeDistroId('raspbian'), 'debian');
      expect(normalizeDistroId('sles'), 'suse');
      expect(normalizeDistroId('opensuse-leap'), 'suse');
      expect(normalizeDistroId('opensuse-tumbleweed'), 'suse');
    });

    test('unknown ids fall back to linux', () {
      expect(normalizeDistroId('nixos'), 'linux');
      expect(normalizeDistroId(''), 'linux');
    });
  });

  group('osIconAsset', () {
    test('known key resolves to asset path', () {
      expect(osIconAsset('ubuntu'), 'assets/os/ubuntu.svg');
      expect(osIconAsset('macos'), 'assets/os/macos.svg');
    });

    test('null and unknown return null', () {
      expect(osIconAsset(null), isNull);
      expect(osIconAsset('beos'), isNull);
    });

    test('alias round-trips through normalizeDistroId to an asset', () {
      expect(osIconAsset(normalizeDistroId('amzn')), 'assets/os/amazon.svg');
    });
  });

  group('icon assets', () {
    test('every kOsIconKeys entry has an svg on disk', () {
      // flutter test runs with cwd = app/
      for (final key in kOsIconKeys) {
        expect(File('assets/os/$key.svg').existsSync(), isTrue,
            reason: 'missing assets/os/$key.svg');
      }
    });
  });
}
