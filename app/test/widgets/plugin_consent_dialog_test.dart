import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/plugin_engine_provider.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh/widgets/plugin_consent_dialog.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

PluginManifest _m(String id) => PluginManifest(
  id: id,
  name: id,
  version: '1.0.0',
  entry: 'index.js',
  minAppVersion: '1.0.0',
  permissions: const {'ui.notify'},
);

void main() {
  testWidgets('Enter denies the plugin (Deny holds default focus)', (
    tester,
  ) async {
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
    final provider = PluginEngineProvider(
      engine: engine,
      loader: loader,
      hookBus: bus,
      uiRegistry: registry,
    );
    provider.setPendingConsent('a', _m('a'), '/p/a');

    await tester.pumpWidget(
      ChangeNotifierProvider<PluginEngineProvider>.value(
        value: provider,
        child: MaterialApp(
          builder: ysRootBuilder,
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => showYsDialog<void>(
                c,
                barrierDismissible: false,
                builder: (_) => PluginConsentDialog(manifest: _m('a')),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final deny = tester.widget<FButton>(
      find.ancestor(of: find.text('Deny'), matching: find.byType(FButton)),
    );
    expect(deny.autofocus, isTrue);
    expect(provider.pendingConsent?.id, 'a');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(provider.pendingConsent, isNull);
    expect(find.text('Allow selected'), findsNothing);
  });
}
