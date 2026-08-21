// app/test/services/app_discovery_service_test.dart
import 'dart:async';
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

  test('concurrent lookups for one extension share a single query (issue #88)',
      () async {
    // Right-clicking several files of the same unseen type used to fire one
    // full platform query each — on Windows every query spawns PowerShell
    // processes, which pinned the CPU.
    var queryCalls = 0;
    final gate = Completer<void>();
    final service = AppDiscoveryService.withQuerier((_) async {
      queryCalls++;
      await gate.future;
      return [
        const AppOption(name: 'Editor', executablePath: '/e', isDefault: false),
      ];
    });

    final futures = [
      service.getAppsFor('/tmp/a.log'),
      service.getAppsFor('/tmp/b.log'),
      service.getAppsFor('/tmp/c.log'),
    ];
    gate.complete();
    final results = await Future.wait(futures);

    expect(queryCalls, 1);
    expect(results.every((r) => r.length == 1), isTrue);
    // The completed lookup is now cached, not left dangling in flight.
    await service.getAppsFor('/tmp/d.log');
    expect(queryCalls, 1);
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

    test('resolve script never wildcard-scans HKCR (issue #88)', () {
      // The old per-app scan enumerated every class under HKCR
      // (`Registry::HKEY_CLASSES_ROOT\*\shell\open\command`), which pinned
      // the CPU. Lookups must be direct key reads.
      final script = AppDiscoveryService.windowsResolveAppsScript(
          ['notepad.exe', 'notepad++.exe']);
      expect(script, isNot(contains('HKEY_CLASSES_ROOT\\*')));
      expect(script, isNot(contains('Get-ChildItem')));
      expect(script, contains('App Paths'));
      expect(script, contains(r'Registry::HKEY_CLASSES_ROOT\Applications\'));
      expect(script, isNot(contains('HKCR:')));
    });

    test('resolve script batches every exe into one invocation', () {
      final script = AppDiscoveryService.windowsResolveAppsScript(
          ['notepad.exe', 'code.exe', 'notepad++.exe']);
      expect(script, contains(r"@('notepad.exe','code.exe','notepad++.exe')"));
      // One loop over the batch, and the description is read in the same
      // process instead of a second one per app.
      expect(script, contains('foreach (\$n in \$names)'));
      expect(script, contains('GetVersionInfo'));
    });

    test('resolve script doubles single quotes in exe names', () {
      final script =
          AppDiscoveryService.windowsResolveAppsScript(["o'brien.exe"]);
      expect(script, contains("'o''brien.exe'"));
    });

    test('isSafeWindowsExeName accepts plain exe filenames only', () {
      expect(AppDiscoveryService.isSafeWindowsExeName('notepad.exe'), isTrue);
      expect(AppDiscoveryService.isSafeWindowsExeName('notepad++.exe'), isTrue);
      expect(AppDiscoveryService.isSafeWindowsExeName('Sublime Text.exe'),
          isTrue);
      expect(AppDiscoveryService.isSafeWindowsExeName('notepad'), isFalse);
      // OpenWithList values are registry-sourced but still interpolated.
      expect(AppDiscoveryService.isSafeWindowsExeName(r'a$(x).exe'), isFalse);
      expect(AppDiscoveryService.isSafeWindowsExeName('a`b.exe'), isFalse);
      expect(AppDiscoveryService.isSafeWindowsExeName('a";del.exe'), isFalse);
    });

    test('parseWindowsResolvedApps reads name/path/description triples', () {
      final apps = AppDiscoveryService.parseWindowsResolvedApps(
          'notepad.exe\tC:\\Windows\\notepad.exe\tNotepad\r\n'
          'raw.exe\tC:\\Apps\\raw.exe\t\r\n'
          'broken-line\r\n'
          '\r\n');
      expect(apps.map((a) => a.name), ['Notepad', 'raw']);
      expect(apps.first.executablePath, r'C:\Windows\notepad.exe');
      // A binary with no FileDescription falls back to its filename.
      expect(apps.last.executablePath, r'C:\Apps\raw.exe');
    });
  });
}
