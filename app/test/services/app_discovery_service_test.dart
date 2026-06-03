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
    String? receivedPath;
    var existedDuringQuery = false;
    final service = AppDiscoveryService.withQuerier((path) async {
      receivedPath = path;
      existedDuringQuery = File(path).existsSync();
      return [];
    });

    await service.getAppsFor('/nonexistent/dir/foo.xyz');

    expect(receivedPath, isNotNull);
    expect(p.extension(receivedPath!), '.xyz');
    expect(existedDuringQuery, isTrue,
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
}
