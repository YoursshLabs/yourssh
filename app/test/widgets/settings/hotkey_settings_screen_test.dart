import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/settings/hotkey_settings_screen.dart';

import 'settings_harness.dart';

/// Hotkey capture on the Keyboard Shortcuts screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPrefs);

  Finder row(String action) => find.byKey(ValueKey('hotkey-row-$action'));

  testWidgets('lists every hotkey with its combo', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, const HotkeySettingsScreen(), scroll: false);

    for (final label in [
      'Command Palette',
      'New Session',
      'Close Session',
      'Next Session',
      'Previous Session',
      'Toggle Input Bar',
      'Split Horizontal',
      'Split Vertical',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('ctrl+t'), findsOneWidget);
    expect(
      find.text(
        'Click a shortcut to rebind it. Changes are saved immediately.',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('clicking a row records the next combo and saves it', (
    tester,
  ) async {
    final h = SettingsHarness();
    await h.pump(tester, const HotkeySettingsScreen(), scroll: false);

    await tester.tap(row('new_session'));
    await tester.pumpAndSettle();
    expect(find.text('recording...'), findsOneWidget);
    expect(
      find.text('Press a key combo for "New Session"  •  Esc to cancel'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('hotkey-cancel')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(h.settings.hotkeys['new_session'], 'ctrl+shift+y');
    expect(find.text('recording...'), findsNothing);
    expect(find.text('ctrl+shift+y'), findsOneWidget);
  });

  testWidgets('Esc cancels recording without changing the combo', (
    tester,
  ) async {
    final h = SettingsHarness();
    await h.pump(tester, const HotkeySettingsScreen(), scroll: false);

    await tester.tap(row('close_session'));
    await tester.pumpAndSettle();
    expect(find.text('recording...'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('recording...'), findsNothing);
    expect(h.settings.hotkeys['close_session'], 'ctrl+w');
  });

  testWidgets('Cancel button stops recording', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, const HotkeySettingsScreen(), scroll: false);

    await tester.tap(row('split_vertical'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hotkey-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('recording...'), findsNothing);
    expect(find.byKey(const ValueKey('hotkey-cancel')), findsNothing);
  });

  testWidgets('a lone modifier keeps recording', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, const HotkeySettingsScreen(), scroll: false);

    await tester.tap(row('next_session'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('recording...'), findsOneWidget);
    expect(h.settings.hotkeys['next_session'], 'ctrl+tab');
  });
}
