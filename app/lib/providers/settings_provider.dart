import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool autoReconnect = true;
  int reconnectAttempts = 3;
  double fontSize = 13;
  String terminalTheme = 'Dracula';
  bool networkStatsEnabled = false;
  bool tmuxEnabled = false;
  bool commandNotificationsEnabled = true;
  String terminalFont = 'MesloLGS NF';
  String recordingPath = '';
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
    commandNotificationsEnabled = prefs.getBool('commandNotificationsEnabled') ?? true;
    terminalFont = prefs.getString('terminalFont') ?? 'MesloLGS NF';
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final defaultPath = home != null
        ? p.join(home, 'Documents', 'YourSSH', 'Recordings')
        : p.join(Directory.current.path, 'YourSSH', 'Recordings');
    recordingPath = prefs.getString('recordingPath') ?? defaultPath;
    final hotkeysJson = prefs.getString('hotkeys');
    if (hotkeysJson != null) {
      try {
        final decoded = jsonDecode(hotkeysJson) as Map<String, dynamic>;
        hotkeys = decoded.map((k, v) => MapEntry(k, v as String));
      } catch (e) {
        // Corrupted prefs: keep the built-in defaults rather than crash boot.
        debugPrint('[SettingsProvider] hotkeys JSON malformed, using defaults: $e');
      }
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
    bool? commandNotificationsEnabled,
    String? recordingPath,
  }) async {
    if (autoReconnect != null) this.autoReconnect = autoReconnect;
    if (reconnectAttempts != null) this.reconnectAttempts = reconnectAttempts;
    if (fontSize != null) this.fontSize = fontSize;
    if (terminalTheme != null) this.terminalTheme = terminalTheme;
    if (hotkeys != null) this.hotkeys = hotkeys;
    if (networkStatsEnabled != null) this.networkStatsEnabled = networkStatsEnabled;
    if (tmuxEnabled != null) this.tmuxEnabled = tmuxEnabled;
    if (terminalFont != null) this.terminalFont = terminalFont;
    if (commandNotificationsEnabled != null) this.commandNotificationsEnabled = commandNotificationsEnabled;
    if (recordingPath != null) this.recordingPath = recordingPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoReconnect', this.autoReconnect);
    await prefs.setInt('reconnectAttempts', this.reconnectAttempts);
    await prefs.setDouble('fontSize', this.fontSize);
    await prefs.setString('terminalTheme', this.terminalTheme);
    await prefs.setString('hotkeys', jsonEncode(this.hotkeys));
    await prefs.setBool('networkStatsEnabled', this.networkStatsEnabled);
    await prefs.setBool('tmuxEnabled', this.tmuxEnabled);
    await prefs.setString('terminalFont', this.terminalFont);
    await prefs.setBool('commandNotificationsEnabled', this.commandNotificationsEnabled);
    await prefs.setString('recordingPath', this.recordingPath);
    notifyListeners();
  }
}
