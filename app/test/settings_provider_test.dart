import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
