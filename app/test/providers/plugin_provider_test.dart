import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:flutter/material.dart';

class _FakePlugin extends YourSSHPlugin {
  @override String get id => 'test.fake';
  @override String get name => 'Fake';
  @override String get description => 'A fake plugin';
  @override IconData get icon => Icons.star;
  @override String get version => '1.0.0';
  @override String get minApiVersion => '1.0.0';
  @override Widget buildUI(BuildContext context, YourSSHPluginContext ctx) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('plugin disabled by default', () async {
    final provider = PluginProvider(plugins: [_FakePlugin()]);
    await provider.loadFromPrefs();
    expect(provider.isEnabled('test.fake'), false);
    expect(provider.enabledPlugins, isEmpty);
  });

  test('toggle enables plugin', () async {
    final provider = PluginProvider(plugins: [_FakePlugin()]);
    await provider.loadFromPrefs();
    await provider.toggle('test.fake');
    expect(provider.isEnabled('test.fake'), true);
    expect(provider.enabledPlugins, hasLength(1));
  });

  test('toggle twice disables plugin', () async {
    final provider = PluginProvider(plugins: [_FakePlugin()]);
    await provider.loadFromPrefs();
    await provider.toggle('test.fake');
    await provider.toggle('test.fake');
    expect(provider.isEnabled('test.fake'), false);
  });

  test('enabled state persists across instances', () async {
    final p1 = PluginProvider(plugins: [_FakePlugin()]);
    await p1.loadFromPrefs();
    await p1.toggle('test.fake');

    final p2 = PluginProvider(plugins: [_FakePlugin()]);
    await p2.loadFromPrefs();
    expect(p2.isEnabled('test.fake'), true);
  });
}
