import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh/mobile/terminal/terminal_side_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the four tabs', (t) async {
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
          ChangeNotifierProvider(create: (_) => SnippetProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTerminalSidePanel(
                    ctx,
                    sessionId: 's1',
                    onInsert: (_) {},
                    onKey: (k, {ctrl = false, alt = false}) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Themes'), findsOneWidget);
  });
}
