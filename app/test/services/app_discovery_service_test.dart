// app/test/services/app_discovery_service_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/services/app_discovery_service.dart';

void main() {
  test('querier receives an existing probe file when given path is missing',
      () async {
    // macOS Launch Services and Linux xdg-mime both return nothing for
    // nonexistent paths, so the service must materialize a probe file.
    // (The empty result triggers the .txt fallback, hence two queries.)
    final receivedPaths = <String>[];
    var allExistedDuringQuery = true;
    final service = AppDiscoveryService.withQuerier((path) async {
      receivedPaths.add(path);
      if (!File(path).existsSync()) allExistedDuringQuery = false;
      return [];
    });

    await service.getAppsFor('/nonexistent/dir/foo.xyz');

    expect(receivedPaths, isNotEmpty);
    expect(p.extension(receivedPaths.first), '.xyz');
    expect(allExistedDuringQuery, isTrue,
        reason: 'probe file must exist while the platform query runs');
    service.dispose();
  });

  test('querier receives the original path when the file exists', () async {
    final real = File(
        '${Directory.systemTemp.createTempSync('yourssh_disc').path}/a.txt')
      ..writeAsStringSync('x');
    String? receivedPath;
    final service = AppDiscoveryService.withQuerier((path) async {
      receivedPath = path;
      return [];
    });

    await service.getAppsFor(real.path);

    expect(receivedPath, real.path);
    service.dispose();
  });

  test('falls back to .txt apps when the extension has no handlers', () async {
    // macOS/Linux register no handler for extensions like .conf or .service,
    // but in an SSH context those are plain text — text editors must show up.
    final queriedExts = <String>[];
    final service = AppDiscoveryService.withQuerier((path) async {
      final ext = p.extension(path);
      queriedExts.add(ext);
      if (ext == '.txt') {
        return [
          const AppOption(
              name: 'Editor', executablePath: '/e', isDefault: false),
        ];
      }
      return [];
    });

    final apps = await service.getAppsFor('/etc/nginx/nginx.conf');

    expect(apps.map((a) => a.name), ['Editor']);
    expect(queriedExts, ['.conf', '.txt']);

    // Second lookup for the same extension is served from the cache.
    await service.getAppsFor('/etc/other.conf');
    expect(queriedExts, ['.conf', '.txt']);
    service.dispose();
  });

  test('cache returns same list on second call without re-querying', () async {
    var queryCalls = 0;
    final service = AppDiscoveryService.withQuerier((_) async {
      queryCalls++;
      return [
        const AppOption(
            name: 'Test App',
            executablePath: '/usr/bin/test',
            isDefault: false),
      ];
    });

    final first = await service.getAppsFor('/tmp/foo.txt');
    final second = await service.getAppsFor('/tmp/bar.txt');

    expect(queryCalls, 1); // both .txt → same extension → cached
    expect(first, same(second));
    service.dispose();
  });

  test('cache is cleared on dispose', () async {
    var queryCalls = 0;
    final service = AppDiscoveryService.withQuerier((_) async {
      queryCalls++;
      return [];
    });

    await service.getAppsFor('/tmp/foo.txt');
    service.dispose();
    await service.getAppsFor('/tmp/foo.txt');

    expect(queryCalls, 2);
    service.dispose();
  });

  test('returns empty list when querier throws', () async {
    final service = AppDiscoveryService.withQuerier(
        (_) async => throw Exception('platform error'));

    final apps = await service.getAppsFor('/tmp/foo.txt');
    expect(apps, isEmpty);
    service.dispose();
  });

  group('Windows script builders', () {
    test('isSafeWindowsExtension accepts plain extensions only', () {
      expect(AppDiscoveryService.isSafeWindowsExtension('.txt'), isTrue);
      expect(AppDiscoveryService.isSafeWindowsExtension('.7z'), isTrue);
      expect(AppDiscoveryService.isSafeWindowsExtension('.tar-gz'), isTrue);
      expect(AppDiscoveryService.isSafeWindowsExtension(''), isFalse);
      expect(AppDiscoveryService.isSafeWindowsExtension('.t xt'), isFalse);
      // Extensions come from remote SFTP filenames — shell/PS metacharacters
      // must never reach an interpolated command.
      expect(AppDiscoveryService.isSafeWindowsExtension(".txt';del"), isFalse);
      expect(AppDiscoveryService.isSafeWindowsExtension(r'.txt$(x)'), isFalse);
      expect(AppDiscoveryService.isSafeWindowsExtension('.txt&del'), isFalse);
    });

    test('OpenWithList script interpolates the extension (no param binding)',
        () {
      // powershell.exe joins everything after -Command into the command text,
      // so named args after the script string never bind to param().
      final script = AppDiscoveryService.windowsOpenWithListScript('.txt');
      expect(script, contains(r'FileExts\.txt\OpenWithList'));
      expect(script, isNot(contains('param(')));
    });

    test('resolve-exe script uses the provider-qualified HKCR path', () {
      // HKCR: is not a default PSDrive in powershell.exe — only HKLM:/HKCU:
      // are. Registry::HKEY_CLASSES_ROOT needs no drive mounted.
      final script =
          AppDiscoveryService.windowsResolveExeScript('notepad.exe');
      expect(script, contains('Registry::HKEY_CLASSES_ROOT'));
      expect(script, isNot(contains('HKCR:')));
      expect(script, contains('notepad.exe'));
    });

    test('resolve-exe script doubles single quotes in the exe name', () {
      final script =
          AppDiscoveryService.windowsResolveExeScript("o'brien.exe");
      expect(script, contains("o''brien.exe"));
    });

    test('file-description script doubles single quotes in the path', () {
      final script = AppDiscoveryService.windowsFileDescriptionScript(
          r"C:\Apps\O'Brien\app.exe");
      expect(script, contains("O''Brien"));
      expect(script, contains('GetVersionInfo'));
    });
  });
}
