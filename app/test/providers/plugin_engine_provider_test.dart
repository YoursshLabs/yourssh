import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/plugin_engine_provider.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

PluginManifest _m(String id) => PluginManifest(
      id: id,
      name: id,
      version: '1.0.0',
      entry: 'index.js',
      minAppVersion: '1.0.0',
      permissions: const {'ui.notify'},
    );

void main() {
  late PluginEngineProvider provider;

  setUp(() {
    final bus = HookBus();
    final registry = PluginUiRegistry();
    final engine = ScriptEngineService(
      hookBus: bus,
      uiRegistry: registry,
      sshDelegate: null,
      sftpDelegate: null,
    );
    final loader = PluginLoader(
      engine: engine,
      onConsentRequired: (_, _, _) {},
      onError: (_, _) {},
    );
    provider = PluginEngineProvider(
        engine: engine, loader: loader, hookBus: bus, uiRegistry: registry);
  });

  test('queues several pending consents instead of dropping them', () {
    provider.setPendingConsent('a', _m('a'), '/p/a');
    provider.setPendingConsent('b', _m('b'), '/p/b');
    expect(provider.pendingConsent?.id, 'a');
    provider.denyConsent();
    expect(provider.pendingConsent?.id, 'b');
    expect(provider.pendingConsentDir, '/p/b');
    provider.denyConsent();
    expect(provider.pendingConsent, isNull);
  });

  test('re-requesting consent for the same plugin does not duplicate', () {
    provider.setPendingConsent('a', _m('a'), '/p/a');
    provider.setPendingConsent('a', _m('a'), '/p/a');
    provider.denyConsent();
    expect(provider.pendingConsent, isNull);
  });
}
