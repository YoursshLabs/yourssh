import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<ProcessResult> check(String dir) =>
    Process.run('bash', ['../tool/check_ios_bundle.sh', dir]);

void main() {
  late Directory d;
  setUp(() => d = Directory.systemTemp.createTempSync('ios_bundle_'));
  tearDown(() => d.deleteSync(recursive: true));

  test('rejects a bundle containing the QuickJS bridge', () async {
    File('${d.path}/Frameworks/libqjsbridge.dylib').createSync(recursive: true);
    final r = await check(d.path);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('forbidden files or directories'));
    expect(r.stderr, contains('libqjsbridge.dylib'));
  });

  test('rejects a binary carrying the PTY fork symbol', () async {
    File('${d.path}/Frameworks/X.framework/X')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0, ...'_pty_forkpty'.codeUnits, 0]);
    final r = await check(d.path);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('pty_forkpty'));
    expect(r.stderr, contains('X.framework/X'));
  });

  test('rejects an Info.plist with any ATS dictionary', () async {
    for (final body in [
      '<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>',
      '<key>NSAppTransportSecurity</key><dict><key>NSExceptionDomains</key><dict/></dict>',
    ]) {
      File('${d.path}/Info.plist').writeAsStringSync('<plist>$body</plist>');
      final r = await check(d.path);
      expect(r.exitCode, 1, reason: body);
      expect(r.stderr, contains('NSAppTransportSecurity'), reason: body);
    }
  });

  test('matches forbidden names case-insensitively', () async {
    File('${d.path}/Frameworks/LibQuickJS.dylib').createSync(recursive: true);
    expect((await check(d.path)).exitCode, 1);
  });

  test('accepts a clean bundle', () async {
    File('${d.path}/Runner').createSync();
    File('${d.path}/Info.plist').writeAsStringSync('<plist></plist>');
    expect((await check(d.path)).exitCode, 0);
  });
}
