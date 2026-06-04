import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/widgets/local_terminal_pane.dart';

void main() {
  testWidgets('exited pane shows Restart shell and fires onRestart',
      (tester) async {
    final session = LocalSession(
      terminal: Terminal(),
      status: LocalSessionStatus.exited,
    );
    var restarted = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LocalTerminalPane(
          session: session,
          onRestart: () => restarted = true,
        ),
      ),
    ));

    expect(find.text('Shell exited'), findsOneWidget);
    await tester.tap(find.text('Restart shell'));
    expect(restarted, isTrue);
  });

  testWidgets('error pane shows the error message', (tester) async {
    final session = LocalSession(
      terminal: Terminal(),
      status: LocalSessionStatus.error,
    )..errorMessage = 'spawn failed';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LocalTerminalPane(session: session, onRestart: () {}),
      ),
    ));

    expect(find.text('spawn failed'), findsOneWidget);
    expect(find.text('Restart shell'), findsOneWidget);
  });
}
