// Builds and runs test/pty_flow_test.c, the native flow-control unit test.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pty_flow.h credit / chunk flow control', () async {
    final cc = Platform.environment['CC'] ?? 'cc';
    final out = Directory.systemTemp.createTempSync('pty_flow_');
    addTearDown(() => out.deleteSync(recursive: true));
    final bin = '${out.path}/pty_flow_test';
    final c = await Process.run(
        cc, ['-O1', '-pthread', '-o', bin, 'test/pty_flow_test.c']);
    expect(c.exitCode, 0, reason: '${c.stdout}${c.stderr}');
    final r = await Process.run(bin, const [])
        .timeout(const Duration(seconds: 60));
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('ok'));
  });
}
