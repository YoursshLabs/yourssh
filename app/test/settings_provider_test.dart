import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/keyword_highlight_rule.dart';
import 'package:yourssh/providers/settings_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('terminalFont defaults to MesloLGS NF', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalFont, 'MesloLGS NF');
  });

  test('auditRetentionDays defaults to 90 and round-trips', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.auditRetentionDays, 90);
    await provider.save(auditRetentionDays: 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('auditRetentionDays'), 30);
    final reloaded = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(reloaded.auditRetentionDays, 30);
  });

  test('save persists terminalFont', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(terminalFont: 'DejaVu Sans Mono for Powerline');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('terminalFont'), 'DejaVu Sans Mono for Powerline');
    expect(provider.terminalFont, 'DejaVu Sans Mono for Powerline');
  });

  test('loads persisted terminalFont on init', () async {
    SharedPreferences.setMockInitialValues({
      'terminalFont': 'Inconsolata for Powerline',
    });
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalFont, 'Inconsolata for Powerline');
  });

  test('previewFontSize updates value and notifies without persisting', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    var notified = false;
    provider.addListener(() => notified = true);

    provider.previewFontSize(18);

    expect(provider.fontSize, 18);
    expect(notified, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('fontSize'), isNull);
  });

  test('keepAliveInterval defaults to 10', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.keepAliveInterval, 10);
  });

  test('save persists keepAliveInterval', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(keepAliveInterval: 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('keepAliveInterval'), 30);
    expect(provider.keepAliveInterval, 30);
  });

  test('loads persisted keepAliveInterval on init', () async {
    SharedPreferences.setMockInitialValues({'keepAliveInterval': 60});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.keepAliveInterval, 60);
  });

  test('reconnectAttempts defaults to 0 (unlimited)', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.reconnectAttempts, 0);
  });

  test('split_vertical default avoids the terminal paste combo', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.hotkeys['split_vertical'], 'ctrl+shift+e');
  });

  test('migrates saved split_vertical off ctrl+shift+v', () async {
    SharedPreferences.setMockInitialValues({
      'hotkeys': jsonEncode({
        'new_session': 'ctrl+t',
        'split_vertical': 'ctrl+shift+v',
      }),
    });
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.hotkeys['split_vertical'], 'ctrl+shift+e');
    // Other saved hotkeys are untouched.
    expect(provider.hotkeys['new_session'], 'ctrl+t');
  });

  test('keeps a user-chosen split_vertical binding', () async {
    SharedPreferences.setMockInitialValues({
      'hotkeys': jsonEncode({'split_vertical': 'ctrl+shift+d'}),
    });
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.hotkeys['split_vertical'], 'ctrl+shift+d');
  });

  test('terminalType defaults to xterm-256color', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalType, 'xterm-256color');
  });

  test('save persists terminalType', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(terminalType: 'vt100');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('terminalType'), 'vt100');
    expect(provider.terminalType, 'vt100');
  });

  test('loads persisted terminalType on init', () async {
    SharedPreferences.setMockInitialValues({'terminalType': 'linux'});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalType, 'linux');
  });

  test('dashboard prefs default to grid and name_asc', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.dashboardViewMode, 'grid');
    expect(provider.dashboardSort, 'name_asc');
  });

  test('save persists dashboardViewMode and dashboardSort', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(dashboardViewMode: 'list', dashboardSort: 'created_desc');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dashboardViewMode'), 'list');
    expect(prefs.getString('dashboardSort'), 'created_desc');
    expect(provider.dashboardViewMode, 'list');
    expect(provider.dashboardSort, 'created_desc');
  });

  test('loads persisted dashboard prefs on init', () async {
    SharedPreferences.setMockInitialValues({
      'dashboardViewMode': 'list',
      'dashboardSort': 'host_asc',
    });
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.dashboardViewMode, 'list');
    expect(provider.dashboardSort, 'host_asc');
  });

  group('keyword highlighting', () {
    test('keywordHighlightingEnabled defaults to true', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(provider.keywordHighlightingEnabled, isTrue);
    });

    test('keywordHighlightRules defaults to kDefaultKeywordHighlightRules', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(provider.keywordHighlightRules.length,
          kDefaultKeywordHighlightRules.length);
    });

    test('save persists keywordHighlightingEnabled', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      await provider.save(keywordHighlightingEnabled: false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('keywordHighlightingEnabled'), isFalse);
    });

    test('save persists keywordHighlightRules as JSON', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final rule = AppKeywordHighlightRule(
        id: 'x',
        label: 'Test',
        pattern: 'test',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: const Color(0xFFFF0000),
      );
      await provider.save(keywordHighlightRules: [rule]);
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('keywordHighlightRules');
      expect(json, isNotNull);
      final decoded = jsonDecode(json!) as List;
      expect(decoded.length, 1);
      expect(decoded[0]['id'], 'x');
    });

    test('loads persisted keywordHighlightRules on init', () async {
      final rule = AppKeywordHighlightRule(
        id: 'y',
        label: 'Loaded',
        pattern: 'loaded',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: null,
      );
      SharedPreferences.setMockInitialValues({
        'keywordHighlightRules': jsonEncode([rule.toJson()]),
        'keywordHighlightingEnabled': false,
      });
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(provider.keywordHighlightRules.length, 1);
      expect(provider.keywordHighlightRules[0].id, 'y');
      expect(provider.keywordHighlightingEnabled, isFalse);
    });
  });
}
