import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/cloudflare_tunnel_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/fake_devops_ssh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void seed(List<Map<String, Object?>> tunnels) =>
      SharedPreferences.setMockInitialValues(
          {'tunnels_v1': jsonEncode(tunnels)});

  Map<String, Object?> tunnel(String label, {int port = 3000}) => {
        'id': 'id-$label',
        'label': label,
        'type': 'cloudflare',
        'localPort': port,
      };

  Future<FakeDevopsSsh> pump(
    WidgetTester tester, {
    bool withSession = true,
    bool installed = true,
  }) async {
    final fake = FakeDevopsSsh();
    fake.reply = (cmd) {
      if (cmd.startsWith('which cloudflared')) {
        return (stdout: installed ? '/usr/bin/cloudflared' : '', stderr: '', exitCode: 0);
      }
      if (cmd.contains('cloudflared tunnel --url')) {
        return (
          stdout: 'DIR:/tmp/cf1\nhttps://abc-def.trycloudflare.com\n',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    await tester.pumpWidget(devopsHarness(const CloudflareTunnelScreen(), fake,
        withSession: withSession));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('smoke: empty state, New Tunnel and session hint', (tester) async {
    seed([]);
    await pump(tester, withSession: false);
    expect(find.text('Cloudflare Tunnels'), findsOneWidget);
    expect(find.text('New Tunnel'), findsOneWidget);
    expect(find.text('No tunnels yet'), findsOneWidget);
    expect(find.text('Add a tunnel to expose a local port via Cloudflare.'),
        findsOneWidget);
    expect(find.text('Connect to a host to manage tunnels'), findsOneWidget);
    expect(find.text('Connect to a host first.'), findsOneWidget);
  });

  testWidgets('New Tunnel panel: add, close, tile shows label and port',
      (tester) async {
    seed([]);
    await pump(tester);
    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    expect(find.text('New Cloudflare Tunnel'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('New Cloudflare Tunnel'), findsNothing);

    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tunnel-label')), 'Web');
    await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '8080');
    await tester.tap(find.text('Add Tunnel'));
    await tester.pumpAndSettle();
    expect(find.text('New Cloudflare Tunnel'), findsNothing);
    expect(find.text('Web'), findsOneWidget);
    expect(find.text('Port: 8080'), findsOneWidget);
    expect(find.text('No tunnels yet'), findsNothing);
  });

  testWidgets('keyboard: label autofocused, Enter on Add Tunnel adds',
      (tester) async {
    seed([]);
    await pump(tester);
    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tunnel-label')), 'Kbd');
    Focus.of(tester.element(find.text('Add Tunnel'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Kbd'), findsOneWidget);
    expect(find.text('Port: 3000'), findsOneWidget);
  });

  testWidgets('start shows URL + copy, stop returns to idle', (tester) async {
    seed([tunnel('Web', port: 3000)]);
    final fake = await pump(tester);
    expect(find.text('Port: 3000'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsOneWidget);

    await tester.tap(find.byTooltip('Start tunnel'));
    await tester.pumpAndSettle();
    expect(fake.cmds.first, 'which cloudflared 2>/dev/null');
    expect(fake.cmds.any((c) => c.contains('cloudflared tunnel --url http://localhost:3000')),
        isTrue);
    expect(find.text('https://abc-def.trycloudflare.com'), findsOneWidget);
    expect(find.byTooltip('Copy URL'), findsOneWidget);
    expect(find.byTooltip('Stop tunnel'), findsOneWidget);

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
    await tester.pump();
    expect(copied, 'https://abc-def.trycloudflare.com');

    await tester.tap(find.byTooltip('Stop tunnel'));
    await tester.pumpAndSettle();
    expect(fake.cmds.last, contains('kill'));
    expect(find.byTooltip('Start tunnel'), findsOneWidget);
  });

  testWidgets('missing cloudflared shows the install hint', (tester) async {
    seed([tunnel('Web')]);
    await pump(tester, installed: false);
    await tester.tap(find.byTooltip('Start tunnel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cloudflared not found on server.'),
        findsOneWidget);
    expect(find.byTooltip('Start tunnel'), findsOneWidget);
  });

  testWidgets('Remove confirm keeps wording, Cancel holds focus',
      (tester) async {
    seed([tunnel('Web')]);
    await pump(tester);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove tunnel'), findsOneWidget);
    expect(find.text('Remove "Web"?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Enter hits the default-focused Cancel: nothing is removed.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Remove tunnel'), findsNothing);
    expect(find.text('Web'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Web'), findsNothing);
    expect(find.text('No tunnels yet'), findsOneWidget);
  });

  testWidgets('900x600 with a 60-char label and panel open does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    seed([tunnel('L' * 60)]);
    await pump(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Start tunnel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
