import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._();
  factory HotkeyService() => _instance;
  HotkeyService._();

  final Map<String, HotKey> _registered = {};

  Future<void> init() async {
    await hotKeyManager.unregisterAll();
  }

  Future<void> register(String name, HotKey hotKey, VoidCallback handler) async {
    if (_registered.containsKey(name)) {
      await hotKeyManager.unregister(_registered[name]!);
    }
    _registered[name] = hotKey;
    await hotKeyManager.register(hotKey, keyDownHandler: (_) => handler());
  }

  Future<void> unregisterAll() async {
    await hotKeyManager.unregisterAll();
    _registered.clear();
  }

  /// Whether [event] matches a registered hotkey combo.
  ///
  /// In-app hotkeys fire at the [HardwareKeyboard] layer, which runs before
  /// focus dispatch but does not consume the event — terminal views call this
  /// from their key handler to swallow the keystroke so it never reaches the
  /// shell as a control sequence (e.g. Ctrl+T also typing ^T).
  bool shouldSwallowKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_registered.isEmpty) return false;
    // Mirrors hotkey_manager's in-app matcher: logical key equality plus an
    // exact modifier-set match derived from the physical keys held down.
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    final heldModifiers = HotKeyModifier.values
        .where((m) => m.physicalKeys.any(pressed.contains))
        .toList();
    return _registered.values.any((hotKey) {
      final modifiers = hotKey.modifiers ?? const [];
      return hotKey.logicalKey == event.logicalKey &&
          heldModifiers.length == modifiers.length &&
          heldModifiers.every(modifiers.contains);
    });
  }

  /// Parses a hotkey string like "ctrl+t", "ctrl+shift+tab", "ctrl+shift+i"
  /// Returns null if the string cannot be parsed.
  static HotKey? parse(String combo) {
    if (combo.isEmpty) return null;
    final parts = combo.toLowerCase().split('+');
    final modifiers = <HotKeyModifier>[];
    LogicalKeyboardKey? key;

    for (final part in parts) {
      switch (part.trim()) {
        case 'ctrl':
        case 'control':
          modifiers.add(HotKeyModifier.control);
        case 'shift':
          modifiers.add(HotKeyModifier.shift);
        case 'alt':
        case 'option':
          modifiers.add(HotKeyModifier.alt);
        case 'meta':
        case 'cmd':
        case 'command':
        case 'win':
          modifiers.add(HotKeyModifier.meta);
        default:
          key = _parseKey(part.trim());
      }
    }

    if (key == null) return null;
    // In-app scope: these are all app-local actions, and the default system
    // scope grabs the combos OS-wide (keybinder/XGrabKey on Linux, which also
    // fails outright on Wayland — issue #46).
    return HotKey(key: key, modifiers: modifiers, scope: HotKeyScope.inapp);
  }

  static const Map<String, LogicalKeyboardKey> _keyMap = {
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
    'tab': LogicalKeyboardKey.tab,
    'enter': LogicalKeyboardKey.enter,
    'escape': LogicalKeyboardKey.escape,
    'esc': LogicalKeyboardKey.escape,
    'space': LogicalKeyboardKey.space,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'del': LogicalKeyboardKey.delete,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
  };

  static LogicalKeyboardKey? _parseKey(String k) => _keyMap[k];
}
