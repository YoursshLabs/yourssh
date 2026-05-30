import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool autoReconnect = true;
  int reconnectAttempts = 3;
  double fontSize = 13;
  String terminalTheme = 'Dracula';
  bool networkStatsEnabled = false;
  bool tmuxEnabled = false;
  bool showWebTools = false;
  bool showSnippets = false;
  bool commandNotificationsEnabled = true;
  String terminalFont = 'MesloLGS NF';
  Map<String, String> hotkeys = {
    'new_session': 'ctrl+t',
    'close_session': 'ctrl+w',
    'next_session': 'ctrl+tab',
    'prev_session': 'ctrl+shift+tab',
    'toggle_input_bar': 'ctrl+shift+i',
    'split_horizontal': 'ctrl+shift+h',
    'split_vertical': 'ctrl+shift+v',
  };

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    autoReconnect = prefs.getBool('autoReconnect') ?? true;
    reconnectAttempts = prefs.getInt('reconnectAttempts') ?? 3;
    fontSize = prefs.getDouble('fontSize') ?? 13;
    terminalTheme = prefs.getString('terminalTheme') ?? 'Dracula';
    networkStatsEnabled = prefs.getBool('networkStatsEnabled') ?? false;
    tmuxEnabled = prefs.getBool('tmuxEnabled') ?? false;
    showWebTools = prefs.getBool('showWebTools') ?? false;
    showSnippets = prefs.getBool('showSnippets') ?? false;
    commandNotificationsEnabled = prefs.getBool('commandNotificationsEnabled') ?? true;
    terminalFont = prefs.getString('terminalFont') ?? 'MesloLGS NF';
    final hotkeysJson = prefs.getString('hotkeys');
    if (hotkeysJson != null) {
      final decoded = jsonDecode(hotkeysJson) as Map<String, dynamic>;
      hotkeys = decoded.map((k, v) => MapEntry(k, v as String));
    }
    notifyListeners();
  }

  Future<void> save({
    bool? autoReconnect,
    int? reconnectAttempts,
    double? fontSize,
    String? terminalTheme,
    Map<String, String>? hotkeys,
    bool? networkStatsEnabled,
    bool? tmuxEnabled,
    String? terminalFont,
    bool? showWebTools,
    bool? showSnippets,
    bool? commandNotificationsEnabled,
  }) async {
    if (autoReconnect != null) this.autoReconnect = autoReconnect;
    if (reconnectAttempts != null) this.reconnectAttempts = reconnectAttempts;
    if (fontSize != null) this.fontSize = fontSize;
    if (terminalTheme != null) this.terminalTheme = terminalTheme;
    if (hotkeys != null) this.hotkeys = hotkeys;
    if (networkStatsEnabled != null) this.networkStatsEnabled = networkStatsEnabled;
    if (tmuxEnabled != null) this.tmuxEnabled = tmuxEnabled;
    if (terminalFont != null) this.terminalFont = terminalFont;
    if (showWebTools != null) this.showWebTools = showWebTools;
    if (showSnippets != null) this.showSnippets = showSnippets;
    if (commandNotificationsEnabled != null) this.commandNotificationsEnabled = commandNotificationsEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoReconnect', this.autoReconnect);
    await prefs.setInt('reconnectAttempts', this.reconnectAttempts);
    await prefs.setDouble('fontSize', this.fontSize);
    await prefs.setString('terminalTheme', this.terminalTheme);
    await prefs.setString('hotkeys', jsonEncode(this.hotkeys));
    await prefs.setBool('networkStatsEnabled', this.networkStatsEnabled);
    await prefs.setBool('tmuxEnabled', this.tmuxEnabled);
    await prefs.setString('terminalFont', this.terminalFont);
    await prefs.setBool('showWebTools', this.showWebTools);
    await prefs.setBool('showSnippets', this.showSnippets);
    await prefs.setBool('commandNotificationsEnabled', this.commandNotificationsEnabled);
    notifyListeners();
  }
}
