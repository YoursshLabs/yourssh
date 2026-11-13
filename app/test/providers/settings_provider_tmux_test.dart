import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('fresh mobile install: tmux on, decided once', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    final p = SettingsProvider();
    await pumpEventQueue();
    expect(p.tmuxEnabled, isTrue);
    expect((await SharedPreferences.getInstance()).getBool('tmuxEnabled'),
        isTrue);
  });

  test('existing mobile install without a choice keeps tmux off', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'yourssh.hosts': '[]'});
    final p = SettingsProvider();
    await pumpEventQueue();
    expect(p.tmuxEnabled, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('tmuxEnabled'),
        isFalse);
  });

  test('a stored choice wins', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({'tmuxEnabled': false});
    final p = SettingsProvider();
    await pumpEventQueue();
    expect(p.tmuxEnabled, isFalse);
  });

  test('desktop without a choice stays off and is not persisted', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues({});
    final p = SettingsProvider();
    await pumpEventQueue();
    expect(p.tmuxEnabled, isFalse);
  });
}
