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
    return HotKey(key: key, modifiers: modifiers);
  }

  static LogicalKeyboardKey? _parseKey(String k) {
    switch (k) {
      case 'a': return LogicalKeyboardKey.keyA;
      case 'b': return LogicalKeyboardKey.keyB;
      case 'c': return LogicalKeyboardKey.keyC;
      case 'd': return LogicalKeyboardKey.keyD;
      case 'e': return LogicalKeyboardKey.keyE;
      case 'f': return LogicalKeyboardKey.keyF;
      case 'g': return LogicalKeyboardKey.keyG;
      case 'h': return LogicalKeyboardKey.keyH;
      case 'i': return LogicalKeyboardKey.keyI;
      case 'j': return LogicalKeyboardKey.keyJ;
      case 'k': return LogicalKeyboardKey.keyK;
      case 'l': return LogicalKeyboardKey.keyL;
      case 'm': return LogicalKeyboardKey.keyM;
      case 'n': return LogicalKeyboardKey.keyN;
      case 'o': return LogicalKeyboardKey.keyO;
      case 'p': return LogicalKeyboardKey.keyP;
      case 'q': return LogicalKeyboardKey.keyQ;
      case 'r': return LogicalKeyboardKey.keyR;
      case 's': return LogicalKeyboardKey.keyS;
      case 't': return LogicalKeyboardKey.keyT;
      case 'u': return LogicalKeyboardKey.keyU;
      case 'v': return LogicalKeyboardKey.keyV;
      case 'w': return LogicalKeyboardKey.keyW;
      case 'x': return LogicalKeyboardKey.keyX;
      case 'y': return LogicalKeyboardKey.keyY;
      case 'z': return LogicalKeyboardKey.keyZ;
      case '0': return LogicalKeyboardKey.digit0;
      case '1': return LogicalKeyboardKey.digit1;
      case '2': return LogicalKeyboardKey.digit2;
      case '3': return LogicalKeyboardKey.digit3;
      case '4': return LogicalKeyboardKey.digit4;
      case '5': return LogicalKeyboardKey.digit5;
      case '6': return LogicalKeyboardKey.digit6;
      case '7': return LogicalKeyboardKey.digit7;
      case '8': return LogicalKeyboardKey.digit8;
      case '9': return LogicalKeyboardKey.digit9;
      case 'tab': return LogicalKeyboardKey.tab;
      case 'enter': return LogicalKeyboardKey.enter;
      case 'escape':
      case 'esc': return LogicalKeyboardKey.escape;
      case 'space': return LogicalKeyboardKey.space;
      case 'backspace': return LogicalKeyboardKey.backspace;
      case 'delete':
      case 'del': return LogicalKeyboardKey.delete;
      case 'up': return LogicalKeyboardKey.arrowUp;
      case 'down': return LogicalKeyboardKey.arrowDown;
      case 'left': return LogicalKeyboardKey.arrowLeft;
      case 'right': return LogicalKeyboardKey.arrowRight;
      case 'f1': return LogicalKeyboardKey.f1;
      case 'f2': return LogicalKeyboardKey.f2;
      case 'f3': return LogicalKeyboardKey.f3;
      case 'f4': return LogicalKeyboardKey.f4;
      case 'f5': return LogicalKeyboardKey.f5;
      case 'f6': return LogicalKeyboardKey.f6;
      case 'f7': return LogicalKeyboardKey.f7;
      case 'f8': return LogicalKeyboardKey.f8;
      case 'f9': return LogicalKeyboardKey.f9;
      case 'f10': return LogicalKeyboardKey.f10;
      case 'f11': return LogicalKeyboardKey.f11;
      case 'f12': return LogicalKeyboardKey.f12;
      default: return null;
    }
  }
}
