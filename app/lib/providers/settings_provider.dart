import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool autoReconnect = true;
  int reconnectAttempts = 3;
  double fontSize = 13;
  String terminalTheme = 'Dracula';

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    autoReconnect = prefs.getBool('autoReconnect') ?? true;
    reconnectAttempts = prefs.getInt('reconnectAttempts') ?? 3;
    fontSize = prefs.getDouble('fontSize') ?? 13;
    terminalTheme = prefs.getString('terminalTheme') ?? 'Dracula';
    notifyListeners();
  }

  Future<void> save({
    bool? autoReconnect,
    int? reconnectAttempts,
    double? fontSize,
    String? terminalTheme,
  }) async {
    if (autoReconnect != null) this.autoReconnect = autoReconnect;
    if (reconnectAttempts != null) this.reconnectAttempts = reconnectAttempts;
    if (fontSize != null) this.fontSize = fontSize;
    if (terminalTheme != null) this.terminalTheme = terminalTheme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoReconnect', this.autoReconnect);
    await prefs.setInt('reconnectAttempts', this.reconnectAttempts);
    await prefs.setDouble('fontSize', this.fontSize);
    await prefs.setString('terminalTheme', this.terminalTheme);
    notifyListeners();
  }
}
