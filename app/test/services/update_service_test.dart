import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      expect(svc.isNewerVersion('', '0.1.19'), isFalse);
    });
    test('mixed v-prefix is tolerated', () {
      expect(svc.isNewerVersion('0.1.18', 'v0.1.19'), isTrue);
      expect(svc.isNewerVersion('v0.1.18', '0.1.19'), isTrue);
    });
    test('partial versions fill missing segments with 0', () {
      expect(svc.isNewerVersion('1', '1.0.1'), isTrue);
      expect(svc.isNewerVersion('1.2', '1.2.0'), isFalse);
    });
  });

  group('assetForPlatform', () {
    final svc = UpdateService();
    AppRelease release() => AppRelease.fromJson({
          'tag_name': 'v0.2.0',
          'assets': [
            {'name': 'YourSSH-0.2.0-macOS-arm64.dmg', 'browser_download_url': 'u/mac', 'size': 1},
            {'name': 'YourSSH.Setup.0.2.0-Windows-x64.exe', 'browser_download_url': 'u/winsetup', 'size': 1},
            {'name': 'YourSSH-0.2.0-Windows-x64.exe', 'browser_download_url': 'u/winportable', 'size': 1},
            {'name': 'YourSSH.Setup.0.2.0-Windows-arm64.exe', 'browser_download_url': 'u/winarmsetup', 'size': 1},
            {'name': 'yourssh_0.2.0_amd64.deb', 'browser_download_url': 'u/deb64', 'size': 1},
            {'name': 'YourSSH-0.2.0-Linux-x86_64.tar.gz', 'browser_download_url': 'u/tgz64', 'size': 1},
            {'name': 'yourssh_0.2.0_arm64.deb', 'browser_download_url': 'u/debarm', 'size': 1},
          ],
        });

    test('macOS arm64 -> dmg', () {
      expect(svc.assetForPlatform(release(), os: 'macos', arch: 'arm64')!.name,
          'YourSSH-0.2.0-macOS-arm64.dmg');
    });
    test('macOS x64 -> null (no Intel artifact)', () {
      expect(svc.assetForPlatform(release(), os: 'macos', arch: 'x64'), isNull);
    });
    test('Windows x64 prefers Setup installer over portable', () {
      expect(svc.assetForPlatform(release(), os: 'windows', arch: 'x64')!.name,
          'YourSSH.Setup.0.2.0-Windows-x64.exe');
    });
    test('Windows arm64 -> arm64 Setup', () {
      expect(svc.assetForPlatform(release(), os: 'windows', arch: 'arm64')!.name,
          'YourSSH.Setup.0.2.0-Windows-arm64.exe');
    });
    test('Linux amd64 prefers .deb over tar.gz', () {
      expect(svc.assetForPlatform(release(), os: 'linux', arch: 'amd64')!.name,
          'yourssh_0.2.0_amd64.deb');
    });
    test('Linux arm64 -> arm64 .deb', () {
      expect(svc.assetForPlatform(release(), os: 'linux', arch: 'arm64')!.name,
          'yourssh_0.2.0_arm64.deb');
    });
    test('Windows x64 falls back to portable when no Setup present', () {
      final noSetup = AppRelease.fromJson({
        'tag_name': 'v0.2.0',
        'assets': [
          {'name': 'YourSSH-0.2.0-Windows-x64.exe', 'browser_download_url': 'u/portable', 'size': 1},
        ],
      });
      expect(svc.assetForPlatform(noSetup, os: 'windows', arch: 'x64')!.name,
          'YourSSH-0.2.0-Windows-x64.exe');
    });
    test('Linux amd64 falls back to tar.gz when no deb present', () {
      final noDeb = AppRelease.fromJson({
        'tag_name': 'v0.2.0',
        'assets': [
          {'name': 'YourSSH-0.2.0-Linux-x86_64.tar.gz', 'browser_download_url': 'u/tgz', 'size': 1},
        ],
      });
      expect(svc.assetForPlatform(noDeb, os: 'linux', arch: 'amd64')!.name,
          'YourSSH-0.2.0-Linux-x86_64.tar.gz');
    });
    test('unknown os -> null', () {
      expect(svc.assetForPlatform(release(), os: 'freebsd', arch: 'x64'), isNull);
    });
  });

  group('fetchLatestRelease', () {
    test('parses a 200 response', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(),
            'https://api.github.com/repos/YoursshLabs/yourssh/releases/latest');
        expect(req.headers['Accept'], 'application/vnd.github+json');
        return http.Response(
          jsonEncode({'tag_name': 'v0.2.0', 'assets': []}),
          200,
        );
      });
      final svc = UpdateService(client: client);
      final r = await svc.fetchLatestRelease();
      expect(r.version, '0.2.0');
    });

    test('throws UpdateException on non-200 (e.g. rate limit)', () async {
      final client = MockClient((req) async => http.Response('rate limited', 403));
      final svc = UpdateService(client: client);
      await expectLater(svc.fetchLatestRelease(), throwsA(isA<UpdateException>()));
    });
  });

  group('downloadAsset', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('update_service_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    ReleaseAsset asset({String? digest}) => ReleaseAsset(
          name: 'test.dmg',
          downloadUrl: 'https://example.com/test.dmg',
          size: 11,
          digest: digest,
        );

    test('non-HTTPS URL throws UpdateException', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response('', 200)),
        downloadDir: tmpDir,
      );
      final bad = ReleaseAsset(
        name: 'test.dmg',
        downloadUrl: 'http://example.com/test.dmg',
        size: 0,
      );
      await expectLater(
        svc.downloadAsset(bad, onProgress: (_) {}),
        throwsA(isA<UpdateException>()),
      );
    });

    test('correct digest passes and file contains downloaded bytes', () async {
      // sha256("hello world") = b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
      const body = 'hello world';
      const expectedDigest =
          'sha256:b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
      final client = MockClient(
        (_) async => http.Response(body, 200),
      );
      final svc = UpdateService(client: client, downloadDir: tmpDir);
      final file = await svc.downloadAsset(
        asset(digest: expectedDigest),
        onProgress: (_) {},
      );
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), body);
    });

    test('digest mismatch throws UpdateException and deletes file', () async {
      final client = MockClient(
        (_) async => http.Response('hello world', 200),
      );
      final svc = UpdateService(client: client, downloadDir: tmpDir);
      await expectLater(
        svc.downloadAsset(
          asset(digest: 'sha256:0000000000000000000000000000000000000000000000000000000000000000'),
          onProgress: (_) {},
        ),
        throwsA(isA<UpdateException>()),
      );
      // File must have been deleted on mismatch.
      expect(File('${tmpDir.path}/test.dmg').existsSync(), isFalse);
    });

    test('null digest skips verification and succeeds', () async {
      final client = MockClient(
        (_) async => http.Response('some binary', 200),
      );
      final svc = UpdateService(client: client, downloadDir: tmpDir);
      final file = await svc.downloadAsset(asset(), onProgress: (_) {});
      expect(file.existsSync(), isTrue);
    });
  });
}
