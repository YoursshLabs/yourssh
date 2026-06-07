import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/keyword_highlight_rule.dart';
import '../models/shell_profile.dart';

/// Default audit-log retention — single source for the provider, its
/// loader, and the launch-time prune in main.dart.
const kDefaultAuditRetentionDays = 90;

/// TERM presets offered by Settings → Terminal and the per-host override.
const kTermTypes = ['xterm-256color', 'xterm', 'linux', 'vt100'];

class SettingsProvider extends ChangeNotifier {
  bool autoReconnect = true;
  int reconnectAttempts = 0;
  int keepAliveInterval = 10;
  double fontSize = 13;
  String terminalTheme = 'Dracula';
  bool networkStatsEnabled = false;
  bool tmuxEnabled = false;
  bool commandNotificationsEnabled = false;
  bool shellIntegrationEnabled = true;
  bool recordingRedactionEnabled = true;
  String terminalFont = 'MesloLGS NF';
  String terminalType = 'xterm-256color';
  String recordingPath = '';

  /// Audit log retention in days; 0 = keep forever.
  int auditRetentionDays = kDefaultAuditRetentionDays;

  /// Hosts dashboard layout: 'grid' (cards) or 'list' (compact rows).
  /// Anything else is treated as 'grid' at the point of use.
  String dashboardViewMode = 'grid';

  /// Hosts dashboard ordering; a HostSortMode key. Unknown values fall
  /// back to name_asc via HostSortMode.fromKey.
  String dashboardSort = 'name_asc';

  /// Default shell id for new local terminals; null = platform default
  /// (today's resolveShell behavior).
  String? defaultShellId;

  /// User-added shells; the only profiles that persist.
  List<ShellProfile> customShellProfiles = [];

  /// Shells found on this machine; re-detected each launch by main.dart via
  /// setDetectedShells, never persisted (ids are stable across launches).
  List<ShellProfile> detectedShellProfiles = [];

  bool keywordHighlightingEnabled = true;
  List<AppKeywordHighlightRule> keywordHighlightRules = kDefaultKeywordHighlightRules;

  List<ShellProfile> get allShellProfiles =>
      [...detectedShellProfiles, ...customShellProfiles];

  Map<String, String> hotkeys = {
    'new_session': 'ctrl+t',
    'close_session': 'ctrl+w',
    'next_session': 'ctrl+tab',
    'prev_session': 'ctrl+shift+tab',
    'toggle_input_bar': 'ctrl+shift+i',
    'split_horizontal': 'ctrl+shift+h',
    // Not ctrl+shift+v: that is terminal paste on Windows/Linux (issue #43).
    'split_vertical': 'ctrl+shift+e',
    'command_palette': Platform.isMacOS ? 'meta+k' : 'ctrl+k',
  };

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    autoReconnect = prefs.getBool('autoReconnect') ?? true;
    reconnectAttempts = prefs.getInt('reconnectAttempts') ?? 0;
    keepAliveInterval = prefs.getInt('keepAliveInterval') ?? 10;
    fontSize = prefs.getDouble('fontSize') ?? 13;
    terminalTheme = prefs.getString('terminalTheme') ?? 'Dracula';
    networkStatsEnabled = prefs.getBool('networkStatsEnabled') ?? false;
    tmuxEnabled = prefs.getBool('tmuxEnabled') ?? false;
    commandNotificationsEnabled = prefs.getBool('commandNotificationsEnabled') ?? false;
    shellIntegrationEnabled = prefs.getBool('shellIntegrationEnabled') ?? true;
    recordingRedactionEnabled = prefs.getBool('recordingRedactionEnabled') ?? true;
    terminalFont = prefs.getString('terminalFont') ?? 'MesloLGS NF';
    terminalType = prefs.getString('terminalType') ?? 'xterm-256color';
    auditRetentionDays =
        prefs.getInt('auditRetentionDays') ?? kDefaultAuditRetentionDays;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final defaultPath = home != null
        ? p.join(home, 'Documents', 'YourSSH', 'Recordings')
        : p.join(Directory.current.path, 'YourSSH', 'Recordings');
    recordingPath = prefs.getString('recordingPath') ?? defaultPath;
    dashboardViewMode = prefs.getString('dashboardViewMode') ?? 'grid';
    dashboardSort = prefs.getString('dashboardSort') ?? 'name_asc';
    defaultShellId = prefs.getString('defaultShellId');
    final shellsJson = prefs.getString('customShellProfiles');
    if (shellsJson != null) {
      try {
        customShellProfiles = (jsonDecode(shellsJson) as List<dynamic>)
            .map((j) => ShellProfile.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // Corrupted prefs: keep defaults rather than crash boot.
        debugPrint(
            '[SettingsProvider] customShellProfiles JSON malformed: $e');
      }
    }
    final hotkeysJson = prefs.getString('hotkeys');
    if (hotkeysJson != null) {
      try {
        final decoded = jsonDecode(hotkeysJson) as Map<String, dynamic>;
        hotkeys = decoded.map((k, v) => MapEntry(k, v as String));
        // Migrate the old split_vertical default off ctrl+shift+v — hotkeys
        // now swallow their combo in terminal views, so leaving it would
        // shadow terminal paste on Windows/Linux (issues #43, #46).
        if (hotkeys['split_vertical'] == 'ctrl+shift+v') {
          hotkeys['split_vertical'] = 'ctrl+shift+e';
        }
      } catch (e) {
        // Corrupted prefs: keep the built-in defaults rather than crash boot.
        debugPrint('[SettingsProvider] hotkeys JSON malformed, using defaults: $e');
      }
    }
    keywordHighlightingEnabled =
        prefs.getBool('keywordHighlightingEnabled') ?? true;
    final rulesJson = prefs.getString('keywordHighlightRules');
    if (rulesJson != null) {
      try {
        keywordHighlightRules = (jsonDecode(rulesJson) as List<dynamic>)
            .map((j) => AppKeywordHighlightRule.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        keywordHighlightRules = kDefaultKeywordHighlightRules;
      }
    }
    notifyListeners();
  }

  /// Live font-size preview while dragging the slider: updates listeners
  /// (terminals resize immediately) without writing SharedPreferences.
  /// Call [save] with the final value when the drag ends.
  void previewFontSize(double value) {
    fontSize = value;
    notifyListeners();
  }

  Future<void> save({
    bool? autoReconnect,
    int? reconnectAttempts,
    int? keepAliveInterval,
    double? fontSize,
    String? terminalTheme,
    Map<String, String>? hotkeys,
    bool? networkStatsEnabled,
    bool? tmuxEnabled,
    String? terminalFont,
    String? terminalType,
    bool? commandNotificationsEnabled,
    bool? shellIntegrationEnabled,
    bool? recordingRedactionEnabled,
    String? recordingPath,
    String? dashboardViewMode,
    String? dashboardSort,
    int? auditRetentionDays,
    bool? keywordHighlightingEnabled,
    List<AppKeywordHighlightRule>? keywordHighlightRules,
  }) async {
    if (autoReconnect != null) this.autoReconnect = autoReconnect;
    if (reconnectAttempts != null) this.reconnectAttempts = reconnectAttempts;
    if (keepAliveInterval != null) this.keepAliveInterval = keepAliveInterval;
    if (fontSize != null) this.fontSize = fontSize;
    if (terminalTheme != null) this.terminalTheme = terminalTheme;
    if (hotkeys != null) this.hotkeys = hotkeys;
    if (networkStatsEnabled != null) this.networkStatsEnabled = networkStatsEnabled;
    if (tmuxEnabled != null) this.tmuxEnabled = tmuxEnabled;
    if (terminalFont != null) this.terminalFont = terminalFont;
    if (terminalType != null) this.terminalType = terminalType;
    if (commandNotificationsEnabled != null) this.commandNotificationsEnabled = commandNotificationsEnabled;
    if (shellIntegrationEnabled != null) this.shellIntegrationEnabled = shellIntegrationEnabled;
    if (recordingRedactionEnabled != null) this.recordingRedactionEnabled = recordingRedactionEnabled;
    if (recordingPath != null) this.recordingPath = recordingPath;
    if (dashboardViewMode != null) this.dashboardViewMode = dashboardViewMode;
    if (dashboardSort != null) this.dashboardSort = dashboardSort;
    if (auditRetentionDays != null) {
      this.auditRetentionDays = auditRetentionDays;
    }
    if (keywordHighlightingEnabled != null) this.keywordHighlightingEnabled = keywordHighlightingEnabled;
    if (keywordHighlightRules != null) this.keywordHighlightRules = keywordHighlightRules;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoReconnect', this.autoReconnect);
    await prefs.setInt('reconnectAttempts', this.reconnectAttempts);
    await prefs.setInt('keepAliveInterval', this.keepAliveInterval);
    await prefs.setDouble('fontSize', this.fontSize);
    await prefs.setString('terminalTheme', this.terminalTheme);
    await prefs.setString('hotkeys', jsonEncode(this.hotkeys));
    await prefs.setBool('networkStatsEnabled', this.networkStatsEnabled);
    await prefs.setBool('tmuxEnabled', this.tmuxEnabled);
    await prefs.setString('terminalFont', this.terminalFont);
    await prefs.setString('terminalType', this.terminalType);
    await prefs.setBool('commandNotificationsEnabled', this.commandNotificationsEnabled);
    await prefs.setBool('shellIntegrationEnabled', this.shellIntegrationEnabled);
    await prefs.setBool('recordingRedactionEnabled', this.recordingRedactionEnabled);
    await prefs.setString('recordingPath', this.recordingPath);
    await prefs.setString('dashboardViewMode', this.dashboardViewMode);
    await prefs.setString('dashboardSort', this.dashboardSort);
    await prefs.setInt('auditRetentionDays', this.auditRetentionDays);
    await prefs.setBool('keywordHighlightingEnabled', this.keywordHighlightingEnabled);
    await prefs.setString('keywordHighlightRules', jsonEncode(this.keywordHighlightRules.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  void setDetectedShells(List<ShellProfile> shells) {
    detectedShellProfiles = shells;
    notifyListeners();
  }

  ShellResolution resolveDefaultShell() =>
      resolveShellProfile(allShellProfiles, defaultShellId);

  Future<void> setDefaultShellId(String? id) async {
    defaultShellId = id;
    await _persistShellSettings();
  }

  Future<void> addCustomShellProfile(ShellProfile profile) async {
    customShellProfiles = [...customShellProfiles, profile];
    await _persistShellSettings();
  }

  Future<void> removeCustomShellProfile(String id) async {
    customShellProfiles =
        customShellProfiles.where((s) => s.id != id).toList();
    if (defaultShellId == id) defaultShellId = null;
    await _persistShellSettings();
  }

  Future<void> _persistShellSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customShellProfiles',
        jsonEncode([for (final s in customShellProfiles) s.toJson()]));
    if (defaultShellId == null) {
      await prefs.remove('defaultShellId');
    } else {
      await prefs.setString('defaultShellId', defaultShellId!);
    }
    notifyListeners();
  }
}
