import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/widgets/web_tools/port_forward_browser.dart';

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pump(
    WidgetTester tester,
    List<PortForward> forwards,
  ) async {
    final provider = PortForwardProvider();
    await provider.ready;
    for (final f in forwards) {
      await provider.add(f);
      provider.setStatus(f.id, f.status);
    }
    final opened = <String>[];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: ysTestApp(PortForwardBrowser(onOpenUrl: opened.add)),
    ));
    await tester.pump();
    return opened;
  }

  PortForward fwd(String label,
          {ForwardType type = ForwardType.local,
          ForwardStatus status = ForwardStatus.active,
          int port = 8080}) =>
      PortForward(
        label: label,
        type: type,
        localPort: port,
        status: status,
      );

  testWidgets('smoke: empty state when no active local tunnel', (tester) async {
    await pump(tester, [
      fwd('idle', status: ForwardStatus.idle),
      fwd('remote', type: ForwardType.remote),
    ]);
    expect(find.text('No active local tunnels'), findsOneWidget);
    expect(
      find.text('Start a local port forward in the Port Forwarding section\n'
          'to open it here.'),
      findsOneWidget,
    );
  });

  testWidgets('lists only active local tunnels with URL, copy and Open',
      (tester) async {
    final opened = await pump(tester, [
      fwd('Web', port: 8080),
      fwd('Other', port: 9090, status: ForwardStatus.idle),
    ]);
    expect(find.text('Active Local Tunnels'), findsOneWidget);
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
    expect(find.text('http://127.0.0.1:8080'), findsOneWidget);
    expect(find.byTooltip('Copy URL'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byTooltip('Copy URL'));
    await tester.pumpAndSettle();
    expect(copied, 'http://127.0.0.1:8080');

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, ['http://127.0.0.1:8080']);
  });

  testWidgets('keyboard: Enter on the focused Open button opens the URL',
      (tester) async {
    final opened = await pump(tester, [fwd('Web')]);
    Focus.of(tester.element(find.text('Open'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, ['http://127.0.0.1:8080']);
  });

  testWidgets('900x600 with a 60-char label and host does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = fwd('L' * 60)..localHost = '${'h' * 60}.example.com';
    await pump(tester, [f]);
    expect(tester.takeException(), isNull);
  });
}
