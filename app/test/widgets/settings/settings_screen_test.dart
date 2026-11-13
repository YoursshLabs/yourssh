import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/settings_screen.dart';

import 'settings_harness.dart';

/// The whole Settings page: sections present, the 900×600 window minimum
/// with long values, and keyboard order through the first section.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secure = FakeSecureStore();
  setUp(() {
    mockPrefs();
    secure
      ..values.clear()
      ..install();
  });
  tearDown(secure.uninstall);

  final long60 = List.filled(60, 'w').join();

  /// Settings docked right of a 240 px sidebar, as MainScreen lays it out.
  Widget inShell() => const Row(
    children: [
      SizedBox(width: 240),
      Expanded(child: SettingsScreen()),
    ],
  );

  testWidgets('every section is on the page', (tester) async {
    final h = SettingsHarness();
    await h.pump(
      tester,
      inShell(),
      size: const Size(1000, 6000),
      scroll: false,
    );

    expect(find.text('Settings'), findsOneWidget);
    for (final section in [
      'Connection',
      'Appearance',
      'Terminal',
      'Keyword highlighting',
      'Recording',
      'Monitoring',
      'Audit',
      'Security',
      'Sync',
      'AI providers',
      'Keyboard',
      'Updates',
    ]) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
  });

  for (final size in const [Size(900, 600), Size(1600, 1000)]) {
    testWidgets('no overflow at ${size.width.toInt()}×${size.height.toInt()} '
        'with long values', (tester) async {
      mockPrefs({
        'recordingPath': '/Users/someone/Documents/$long60/Recordings',
        'customShellProfiles': jsonEncode([
          {
            'id': 'custom-long',
            'name': 'Shell $long60',
            'executable': '/opt/$long60/bin/zsh',
            'args': ['--login', long60],
            'isCustom': true,
          },
        ]),
        'keywordHighlightRules': jsonEncode([
          {
            'id': 'r1',
            'label': 'Rule $long60',
            'pattern': 'pattern-$long60',
            'isRegex': true,
            'caseSensitive': false,
            'enabled': true,
            'foreground': 0xFFFFFFFF,
            'background': 0xFFB71C1C,
          },
        ]),
        'terminalFont': 'Custom $long60 Nerd Font',
        'supabase_url': 'https://$long60.supabase.co',
        'supabase_anon_key': long60,
      });
      final h = SettingsHarness();
      await h.pump(tester, inShell(), size: size, scroll: false);
      expect(tester.takeException(), isNull);

      // Scroll through the whole page so every section is laid out on screen.
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 40; i++) {
        await tester.drag(scrollable, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Tab walks the Connection controls in order', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, inShell(), size: const Size(900, 600), scroll: false);

    final order = [
      'settings-auto-reconnect',
      'settings-reconnect-attempts',
      'settings-keep-alive',
      'settings-tmux',
      'settings-shell-integration',
    ];
    for (final key in order) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(hasFocusWithin(tester, ValueKey(key)), isTrue, reason: key);
    }
  });

  testWidgets('Space on the focused switch toggles it', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, inShell(), size: const Size(900, 600), scroll: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      hasFocusWithin(tester, const ValueKey('settings-auto-reconnect')),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(h.settings.autoReconnect, isFalse);
  });
}
