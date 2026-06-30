// Throwaway diagnostic: probe Pty.start on this machine to find out why the
// local shell exits immediately. Delete after debugging.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('probe local shell spawn', () async {
    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
    // ignore: avoid_print
    print('PROBE: spawning "$shell" (HOME=${Platform.environment['HOME']})');

    final pty = Pty.start(
      shell,
      arguments: const [],
      columns: 80,
      rows: 24,
      environment: {...Platform.environment, 'TERM': 'xterm-256color'},
    );

    final output = StringBuffer();
    final sub = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(output.write);

    final exit = await pty.exitCode
        .timeout(const Duration(seconds: 5), onTimeout: () => -9999);

    // ignore: avoid_print
    print('PROBE: exitCode=$exit (−9999 means still alive after 5s = OK)');
    // ignore: avoid_print
    print('PROBE: output so far: ${jsonEncode(output.toString())}');

    await sub.cancel();
    if (exit == -9999) pty.kill();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
