import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yourssh/services/hotkey_service.dart';

void main() {
  group('HotkeyService.parse', () {
    test('parses modifiers and key', () {
      final hotKey = HotkeyService.parse('ctrl+shift+tab')!;
      expect(hotKey.logicalKey, LogicalKeyboardKey.tab);
      expect(
        hotKey.modifiers,
        containsAll([HotKeyModifier.control, HotKeyModifier.shift]),
      );
    });

    test('returns null for unknown keys', () {
      expect(HotkeyService.parse('ctrl+nosuchkey'), isNull);
      expect(HotkeyService.parse(''), isNull);
    });

    // App hotkeys are app-local actions; system-wide grabs are wrong scope
    // (and keybinder/XGrabKey cannot work on Wayland at all — issue #46).
    test('creates in-app scoped hotkeys so Linux never hits keybinder', () {
      expect(HotkeyService.parse('ctrl+t')!.scope, HotKeyScope.inapp);
    });
  });

  group('HotkeyService.shouldSwallowKeyEvent', () {
    testWidgets('swallows a registered combo while its modifiers are held',
        (tester) async {
      final svc = HotkeyService();
      await svc.register('swallow_match', HotkeyService.parse('ctrl+t')!, () {});

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

      const down = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyT,
        logicalKey: LogicalKeyboardKey.keyT,
        timeStamp: Duration.zero,
      );
      expect(svc.shouldSwallowKeyEvent(down), isTrue);

      const repeat = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyT,
        logicalKey: LogicalKeyboardKey.keyT,
        timeStamp: Duration.zero,
      );
      expect(svc.shouldSwallowKeyEvent(repeat), isTrue);

      // A different key under the same modifier must reach the terminal.
      const other = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyY,
        logicalKey: LogicalKeyboardKey.keyY,
        timeStamp: Duration.zero,
      );
      expect(svc.shouldSwallowKeyEvent(other), isFalse);

      // Key-up events are never swallowed (terminal ignores them anyway).
      const up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyT,
        logicalKey: LogicalKeyboardKey.keyT,
        timeStamp: Duration.zero,
      );
      expect(svc.shouldSwallowKeyEvent(up), isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('does not swallow without the registered modifiers held',
        (tester) async {
      final svc = HotkeyService();
      await svc.register(
          'swallow_no_mods', HotkeyService.parse('ctrl+shift+e')!, () {});

      // Bare key: no modifiers pressed.
      const bare = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyE,
        logicalKey: LogicalKeyboardKey.keyE,
        timeStamp: Duration.zero,
      );
      expect(svc.shouldSwallowKeyEvent(bare), isFalse);

      // Only one of the two required modifiers held.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(svc.shouldSwallowKeyEvent(bare), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
  });
}
