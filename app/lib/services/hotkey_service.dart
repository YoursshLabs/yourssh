// app/lib/services/hotkey_service.dart
import 'package:flutter/foundation.dart';
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
}
