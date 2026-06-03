import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/services/update_service.dart';

void main() {
  group('AppRelease.fromJson', () {
    final json = {
      'tag_name': 'v0.2.0',
      'name': 'YourSSH v0.2.0',
      'body': '## Changes\n- thing',
      'html_url': 'https://github.com/YoursshLabs/yourssh/releases/tag/v0.2.0',
      'published_at': '2026-06-01T10:00:00Z',
      'assets': [
        {
          'name': 'YourSSH-0.2.0-macOS-arm64.dmg',
          'browser_download_url': 'https://example.com/a.dmg',
          'size': 1234,
        },
      ],
    };

    test('strips leading v from version', () {
      expect(AppRelease.fromJson(json).version, '0.2.0');
    });

    test('parses tag, name, notes, url and publishedAt', () {
      final r = AppRelease.fromJson(json);
      expect(r.tagName, 'v0.2.0');
      expect(r.name, 'YourSSH v0.2.0');
      expect(r.notes, contains('thing'));
      expect(r.htmlUrl, contains('/tag/v0.2.0'));
      expect(r.publishedAt, DateTime.utc(2026, 6, 1, 10));
    });

    test('parses assets list', () {
      final r = AppRelease.fromJson(json);
      expect(r.assets, hasLength(1));
      expect(r.assets.first.name, 'YourSSH-0.2.0-macOS-arm64.dmg');
      expect(r.assets.first.downloadUrl, 'https://example.com/a.dmg');
      expect(r.assets.first.size, 1234);
    });

    test('ReleaseAsset tolerates a null browser_download_url', () {
      final asset = ReleaseAsset.fromJson(
          {'name': 'source.zip', 'browser_download_url': null, 'size': 0});
      expect(asset.downloadUrl, '');
      expect(asset.name, 'source.zip');
    });
  });

  group('isNewerVersion', () {
    final svc = UpdateService();
    test('equal versions are not newer', () {
      expect(svc.isNewerVersion('0.1.18', '0.1.18'), isFalse);
    });
    test('patch bump is newer', () {
      expect(svc.isNewerVersion('0.1.18', '0.1.19'), isTrue);
    });
    test('minor bump is newer', () {
      expect(svc.isNewerVersion('0.1.18', '0.2.0'), isTrue);
    });
    test('major bump is newer', () {
      expect(svc.isNewerVersion('0.9.9', '1.0.0'), isTrue);
    });
    test('older latest is not newer', () {
      expect(svc.isNewerVersion('0.2.0', '0.1.19'), isFalse);
    });
    test('leading v is tolerated on both sides', () {
      expect(svc.isNewerVersion('v0.1.18', 'v0.1.19'), isTrue);
    });
    test('pre-release / build suffix is ignored', () {
      expect(svc.isNewerVersion('0.1.18', '0.1.18-beta.1'), isFalse);
      expect(svc.isNewerVersion('0.1.18', '0.1.19+5'), isTrue);
    });
    test('unparseable input is treated as not newer (fail closed)', () {
      expect(svc.isNewerVersion('0.1.18', 'garbage'), isFalse);
      expect(svc.isNewerVersion('', '0.1.19'), isTrue);
    });
  });
}
