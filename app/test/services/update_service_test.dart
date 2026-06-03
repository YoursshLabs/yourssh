import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_release.dart';

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
  });
}
