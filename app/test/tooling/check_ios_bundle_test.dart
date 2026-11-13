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
    expect((await check(d.path)).exitCode, isNot(0));
  });

  test('rejects a binary carrying the PTY fork symbol', () async {
    File('${d.path}/Frameworks/X.framework/X')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0, ...'_pty_forkpty'.codeUnits, 0]);
    expect((await check(d.path)).exitCode, isNot(0));
  });

  test('rejects an Info.plist that opts out of ATS', () async {
    File('${d.path}/Info.plist')
        .writeAsStringSync('<plist><key>NSAllowsArbitraryLoads</key></plist>');
    expect((await check(d.path)).exitCode, isNot(0));
  });

  test('accepts a clean bundle', () async {
    File('${d.path}/Runner').createSync();
    File('${d.path}/Info.plist').writeAsStringSync('<plist></plist>');
    expect((await check(d.path)).exitCode, 0);
  });
}
