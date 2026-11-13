import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_web_tools/src/screens/web_tools_screen.dart';
import 'package:yourssh_web_tools/yourssh_web_tools.dart';

import 'helpers/ys_test_app.dart';

void main() {
  testWidgets('WebToolsScreen renders the sub-navigation and switches tools',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ysTestApp(WebToolsScreen(
      config: WebToolsPluginConfig(
        portForwardBrowserBuilder: (_) => const Text('tunnels-body'),
      ),
    )));
    await tester.pump();

    // The default Browser tool needs a webview platform implementation, which
    // the VM test host lacks; the sub-navigation must still render.
    expect(
      tester.takeException().toString(),
      contains('WebViewPlatform.instance'),
    );
    expect(find.text('Web Tools'), findsOneWidget);
    for (final label in ['Browser', 'HTTP Client', 'Utilities', 'Port Tunnels']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Port Tunnels'));
    await tester.pump();
    expect(find.text('tunnels-body'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
