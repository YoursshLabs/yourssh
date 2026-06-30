// Throwaway diagnostic: boot the real app and open a local shell through the
// real SessionProvider/LocalShellService path, then report the session status
// and terminal buffer. Delete after debugging.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/main.dart' as app;
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/providers/session_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('probe real local shell flow', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));

    final context = tester.element(find.byType(Navigator).first);
    final sessions = Provider.of<SessionProvider>(context, listen: false);

    await sessions.newLocalSession();
    // Let the PTY live (or die) for a few seconds of real time.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final local = sessions.sessions.whereType<LocalSession>().toList();
    // ignore: avoid_print
    print('PROBE: ${local.length} local session(s)');
    for (final s in local) {
      // ignore: avoid_print
      print('PROBE: status=${s.status} error=${s.errorMessage}');
      final buf = s.terminal.buffer;
      final lines = <String>[];
      for (var y = 0; y < buf.height; y++) {
        final line = buf.lines[y].toString().trimRight();
        if (line.isNotEmpty) lines.add(line);
      }
      // ignore: avoid_print
      print('PROBE: terminal content:\n${lines.join('\n')}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
