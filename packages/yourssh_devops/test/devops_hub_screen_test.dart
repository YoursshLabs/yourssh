import 'package:flutter/services.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_devops/yourssh_devops.dart';
import 'package:yourssh_devops/src/screens/devops_hub_screen.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'helpers/tab_to.dart';
import 'helpers/ys_test_app.dart';

const _config = DevOpsPluginConfig(
  containersScreen: Text('stub-containers'),
  networkToolsScreen: Text('stub-network'),
  cloudflareScreen: Text('stub-cloudflare'),
  mailCatcherScreen: Text('stub-mail'),
  mcpServerScreen: Text('stub-mcp'),
);

const _tools = [
  ('Containers', 'stub-containers'),
  ('Network Tools', 'stub-network'),
  ('Cloudflare', 'stub-cloudflare'),
  ('Mail Catcher', 'stub-mail'),
  ('MCP Server', 'stub-mcp'),
];

class _Ctx implements YourSSHPluginContext {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  testWidgets('sub-nav lists every tool and defaults to Network Tools', (
    tester,
  ) async {
    await tester.pumpWidget(ysTestApp(const DevOpsHubScreen(config: _config)));
    await tester.pumpAndSettle();
    expect(find.text('DevOps'), findsOneWidget);
    for (final label in [
      'Containers',
      'Network Tools',
      'Cloudflare',
      'LAN Share',
      'Mail Catcher',
      'MCP Server',
      'S3 Browser',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('stub-network'), findsOneWidget);
  });

  testWidgets('selecting a nav item swaps the content', (tester) async {
    await tester.pumpWidget(ysTestApp(const DevOpsHubScreen(config: _config)));
    await tester.pumpAndSettle();
    for (final (label, stub) in _tools) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text(stub), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('LAN Share'));
    await tester.pumpAndSettle();
    expect(find.text('Pick File to Share'), findsOneWidget);
  });

  testWidgets('Tab reaches a nav item and Enter selects it', (tester) async {
    await tester.pumpWidget(ysTestApp(const DevOpsHubScreen(config: _config)));
    await tester.pumpAndSettle();
    expect(await tabTo(tester, find.text('Cloudflare')), greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('stub-cloudflare'), findsOneWidget);
  });

  testWidgets('no overflow at 900x600', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ysTestApp(const DevOpsHubScreen(config: _config)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('plugin root finds the Ys FTheme when pushed as a route', (
    tester,
  ) async {
    final plugin = YourSSHDevOpsPlugin(config: _config);
    await pumpPushedRoute(tester, (c) => plugin.buildUI(c, _Ctx()));
    expect(
      FTheme.of(tester.element(find.text('DevOps'))).colors.primary,
      YsColors.primary,
    );
    expect(find.text('stub-network'), findsOneWidget);
  });
}
