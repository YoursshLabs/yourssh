import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/widgets/cloudflare_tunnel_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/fake_devops_ssh.dart';
import '../helpers/tab_to_control.dart';

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

  testWidgets('keyboard: Enter in label focuses port, Enter in port submits',
      (tester) async {
    seed([]);
    await pump(tester);
    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tunnel-label')), 'Kbd');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final portField = find.descendant(
        of: find.byKey(const ValueKey('tunnel-port')),
        matching: find.byType(EditableText));
    expect(tester.widget<EditableText>(portField).focusNode.hasFocus, isTrue);
    await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '4040');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('New Cloudflare Tunnel'), findsNothing);
    expect(find.text('Kbd'), findsOneWidget);
    expect(find.text('Port: 4040'), findsOneWidget);
  });

  testWidgets('Enter in port with an empty label adds nothing, like the button',
      (tester) async {
    seed([]);
    await pump(tester);
    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tunnel-label')), '  ');
    await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '4040');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('New Cloudflare Tunnel'), findsOneWidget);
    expect(find.text('No tunnels yet'), findsOneWidget);
  });

  group('panel validation', () {
    Future<void> open(WidgetTester tester) async {
      seed([]);
      await pump(tester);
      await tester.tap(find.text('New Tunnel'));
      await tester.pumpAndSettle();
    }

    testWidgets('empty label shows Required and adds nothing (button)',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('tunnel-label')), ' ');
      await tester.tap(find.text('Add Tunnel'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('New Cloudflare Tunnel'), findsOneWidget);
      expect(find.text('No tunnels yet'), findsOneWidget);
    });

    testWidgets('empty label shows Required via Enter in the port field',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('tunnel-label')), '');
      await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '4040');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('No tunnels yet'), findsOneWidget);
    });

    for (final bad in ['0', '65536', '99999']) {
      testWidgets('port "$bad" shows Invalid (1–65535)', (tester) async {
        await open(tester);
        await tester.enterText(find.byKey(const ValueKey('tunnel-port')), bad);
        await tester.tap(find.text('Add Tunnel'));
        await tester.pumpAndSettle();
        expect(find.text('Invalid (1–65535)'), findsOneWidget);
        expect(find.text('No tunnels yet'), findsOneWidget);
      });
    }

    testWidgets('empty port keeps the 3000 default', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '');
      await tester.tap(find.text('Add Tunnel'));
      await tester.pumpAndSettle();
      expect(find.text('Port: 3000'), findsOneWidget);
    });

    testWidgets('fixing the field and resubmitting clears the error',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '0');
      await tester.tap(find.text('Add Tunnel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('tunnel-port')), '8080');
      await tester.tap(find.text('Add Tunnel'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid (1–65535)'), findsNothing);
      expect(find.text('Port: 8080'), findsOneWidget);
    });
  });

  testWidgets('Tab reaches New Tunnel (1) and Add Tunnel (2 from label); Enter',
      (tester) async {
    seed([]);
    await pump(tester);
    expect(await tabToControl(tester, find.byKey(const ValueKey('tunnel-new'))), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('New Cloudflare Tunnel'), findsOneWidget);
    // Label is autofocused: port, then Add Tunnel.
    await tester.enterText(find.byKey(const ValueKey('tunnel-label')), 'Tab');
    final n = await tabToControl(tester, find.byKey(const ValueKey('tunnel-add')));
    expect(n, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Tab'), findsOneWidget);
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

  testWidgets('900x600 with a long public URL and long error does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longHost = 'u' * 40;
    seed([tunnel('Web'), tunnel('Broken', port: 4000)]);
    final fake = await pump(tester);
    fake.reply = (cmd) {
      if (cmd.startsWith('which cloudflared')) {
        return (stdout: '/usr/bin/cloudflared', stderr: '', exitCode: 0);
      }
      if (cmd.contains('--url http://localhost:3000')) {
        return (
          stdout: 'DIR:/tmp/cf1\nhttps://$longHost.trycloudflare.com\n',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: 'DIR:/tmp/cf2\n', stderr: '', exitCode: 0);
    };
    await tester.tap(find.byTooltip('Start tunnel').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Start tunnel').last);
    await tester.pumpAndSettle();
    expect(find.text('https://$longHost.trycloudflare.com'), findsOneWidget);
    expect(find.textContaining('No trycloudflare URL in /tmp/cf2'),
        findsOneWidget);
    await tester.tap(find.text('New Tunnel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
