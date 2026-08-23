import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/theme/terminal_themes.dart';
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

  // The pane used to build xterm's TerminalView without a `theme:` argument,
  // so every local shell rendered in xterm's built-in default palette and the
  // Settings → Terminal color theme silently did nothing.
  testWidgets('running pane renders with the configured color theme',
      (tester) async {
    SharedPreferences.setMockInitialValues({'terminalTheme': 'Nord'});
    final settings = SettingsProvider();
    addTearDown(settings.dispose);

    final session = LocalSession(
      terminal: Terminal(),
      status: LocalSessionStatus.running,
    );

    final recording = RecordingProvider(RecordingService(),
        getPath: () => Directory.systemTemp.path);
    addTearDown(recording.dispose);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: recording),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LocalTerminalPane(session: session, onRestart: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.theme, terminalThemeByName('Nord'));
    expect(view.theme, isNot(TerminalThemes.defaultTheme));
  });
}
