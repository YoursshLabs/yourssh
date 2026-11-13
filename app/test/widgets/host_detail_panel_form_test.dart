import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show YsDialog;

import '../helpers/ys_test_app.dart';

/// Answers Test connection with a canned result instead of dialling.
class _FakeSsh extends SshService {
  _FakeSsh(super.storage, this.result);
  final ({bool success, int latencyMs, String? error}) result;

  @override
  Future<({bool success, int latencyMs, String? error})> testConnection(
    Host host, {
    String? password,
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
  }) async => result;
}

/// Counts dial attempts so a blocked Test connection can be asserted.
class _CountingSsh extends _FakeSsh {
  _CountingSsh(StorageService storage)
    : super(storage, (success: true, latencyMs: 1, error: null));
  int calls = 0;

  @override
  Future<({bool success, int latencyMs, String? error})> testConnection(
    Host host, {
    String? password,
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
  }) async {
    calls++;
    return result;
  }
}

/// Keyboard flow, footer actions, protocol switch and the 900×600 layout of
/// the host editor (Review Focus 1–3 of the UI redesign plan).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Host deletion purges the stored passwords; answer the secure-storage
    // channel so it resolves under pumpAndSettle.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  final long60 = List.filled(60, 'w').join();

  late HostProvider hosts;
  Host? saved;
  var closed = 0;

  Future<void> pumpPanel(
    WidgetTester tester, {
    Host? existing,
    HostProtocol? initialProtocol,
    List<Host> others = const [],
    Size size = const Size(500, 2400),
    bool asApp = false,
    SshService? ssh,
  }) async {
    saved = null;
    closed = 0;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    hosts = HostProvider(StorageService());
    await tester.runAsync(() async {
      await hosts.ready;
      for (final h in [...others, ?existing]) {
        await hosts.addHost(h);
      }
    });
    final panel = HostDetailPanel(
      existing: existing,
      initialProtocol: initialProtocol,
      agentProbe: () async => const AgentProbeSystem(1),
      onClose: () => closed++,
      onSave: (host, _) async => saved = host,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          Provider<SshService>(
            create: (_) => ssh ?? SshService(StorageService()),
          ),
        ],
        // asApp: the panel docked right of a 200 px sidebar and the
        // dashboard, as MainScreen lays it out.
        child: ysTestApp(
          asApp
              ? Row(
                  children: [
                    const SizedBox(width: 200),
                    const Expanded(child: SizedBox.expand()),
                    panel,
                  ],
                )
              : Align(alignment: Alignment.topLeft, child: panel),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Host existingHost({String label = 'srv'}) =>
      Host(id: 'target-id', label: label, host: '1.2.3.4', username: 'root');

  Finder field(String key) => find.byKey(ValueKey(key));

  EditableText editable(WidgetTester tester, String key) =>
      tester.widget<EditableText>(
        find.descendant(of: field(key), matching: find.byType(EditableText)),
      );

  bool focused(WidgetTester tester, String key) =>
      editable(tester, key).focusNode.hasFocus;

  group('keyboard', () {
    testWidgets('Enter in the label field saves', (tester) async {
      await pumpPanel(tester, existing: existingHost());

      await tester.tap(field('host-label-field'));
      await tester.pump();
      await tester.enterText(field('host-label-field'), 'renamed');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(saved, isNotNull, reason: 'Enter submits the form');
      expect(saved!.label, 'renamed');
      expect(closed, 1, reason: 'a successful save closes the panel');
    });

    testWidgets('Enter does not save an invalid form', (tester) async {
      await pumpPanel(tester);

      await tester.tap(field('host-label-field'));
      await tester.pump();
      await tester.enterText(field('host-label-field'), 'no address');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(saved, isNull, reason: 'hostname is required');
      expect(find.text('Required'), findsOneWidget);
      expect(
        focused(tester, 'host-label-field'),
        isTrue,
        reason: 'the caret stays in the field when validation fails',
      );
    });

    testWidgets('Tab order runs label → hostname → port → username', (
      tester,
    ) async {
      await pumpPanel(tester, existing: existingHost());

      await tester.tap(field('host-label-field'));
      await tester.pump();
      expect(focused(tester, 'host-label-field'), isTrue);

      for (final next in [
        'host-address-field',
        'host-port-field',
        'host-username-field',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(focused(tester, next), isTrue, reason: 'Tab reaches $next');
      }
    });

    testWidgets('new host: hostname autofocuses and the order holds', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(
        focused(tester, 'host-address-field'),
        isTrue,
        reason: 'hostname keeps its autofocus',
      );
      // The network scan button sits before the label, never between the
      // label and the hostname.
      expect(find.text('Scan network to pick a device'), findsOneWidget);
      await tester.tap(field('host-label-field'));
      await tester.pump();
      for (final next in [
        'host-address-field',
        'host-port-field',
        'host-username-field',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(focused(tester, next), isTrue, reason: 'Tab reaches $next');
      }
    });
  });

  group('protocol switch', () {
    testWidgets('port auto-flips between protocol defaults', (tester) async {
      await pumpPanel(tester);
      String port() => editable(tester, 'host-port-field').controller.text;
      expect(port(), '22');

      await tester.tap(find.text('VNC'));
      await tester.pumpAndSettle();
      expect(port(), '5900');

      await tester.tap(find.text('RDP'));
      await tester.pumpAndSettle();
      expect(port(), '3389');

      await tester.tap(find.text('SSH'));
      await tester.pumpAndSettle();
      expect(port(), '22');
    });

    testWidgets('a custom port is kept across protocol switches', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.enterText(field('host-port-field'), '2200');
      await tester.tap(find.text('RDP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VNC'));
      await tester.pumpAndSettle();
      expect(editable(tester, 'host-port-field').controller.text, '2200');
    });
  });

  group('port validation', () {
    const msg = 'Invalid (1–65535)';

    // Set the controller directly so the digits-only formatter cannot strip
    // the value first (e.g. a non-numeric one).
    void setPort(WidgetTester tester, String v) =>
        editable(tester, 'host-port-field').controller.text = v;

    for (final bad in ['0', '65536', '70000', 'abc']) {
      testWidgets('"$bad" shows the error and blocks Save', (tester) async {
        await pumpPanel(tester, existing: existingHost());
        setPort(tester, bad);
        await tester.tap(field('host-save-button'));
        await tester.pumpAndSettle();
        expect(find.text(msg), findsOneWidget);
        expect(saved, isNull);
      });
    }

    for (final ok in {'1': 1, '65535': 65535, '': 22}.entries) {
      testWidgets('"${ok.key}" saves as ${ok.value}', (tester) async {
        await pumpPanel(tester, existing: existingHost());
        setPort(tester, ok.key);
        await tester.tap(field('host-save-button'));
        await tester.pumpAndSettle();
        expect(find.text(msg), findsNothing);
        expect(saved?.port, ok.value);
      });
    }

    testWidgets('empty port saves the protocol default (VNC)', (tester) async {
      await pumpPanel(tester, initialProtocol: HostProtocol.vnc);
      await tester.enterText(field('host-address-field'), '1.2.3.4');
      setPort(tester, '');
      await tester.tap(field('host-save-button'));
      await tester.pumpAndSettle();
      expect(saved?.port, 5900);
    });

    testWidgets('Test connection with 70000 does not dial', (tester) async {
      final ssh = _CountingSsh(StorageService());
      await pumpPanel(tester, existing: existingHost(), ssh: ssh);
      setPort(tester, '70000');
      await tester.tap(field('host-test-button'));
      await tester.pumpAndSettle();
      expect(ssh.calls, 0);
      expect(find.text(msg), findsOneWidget);
    });
  });

  group('footer', () {
    testWidgets('SSH host: Delete, Test and Save are present', (tester) async {
      await pumpPanel(tester, existing: existingHost());
      expect(field('host-delete-button'), findsOneWidget);
      expect(field('host-test-button'), findsOneWidget);
      expect(field('host-save-button'), findsOneWidget);
    });

    testWidgets('new host has no Delete', (tester) async {
      await pumpPanel(tester);
      expect(field('host-delete-button'), findsNothing);
      expect(field('host-save-button'), findsOneWidget);
    });

    testWidgets('Delete asks first, and Cancel keeps the host', (tester) async {
      await pumpPanel(tester, existing: existingHost());
      await tester.tap(field('host-delete-button'));
      await tester.pumpAndSettle();

      expect(find.byType(YsDialog), findsOneWidget);
      expect(find.text('Delete host?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(hosts.allHosts.map((h) => h.id), contains('target-id'));
      expect(closed, 0);
    });

    testWidgets('Delete removes the host and closes the panel', (tester) async {
      await pumpPanel(tester, existing: existingHost());
      await tester.tap(field('host-delete-button'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(YsDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(hosts.allHosts.map((h) => h.id), isNot(contains('target-id')));
      expect(closed, 1);
      expect(saved, isNull, reason: 'Delete never saves');
    });

    testWidgets('close button has a tooltip and closes', (tester) async {
      await pumpPanel(tester, existing: existingHost());
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('password visibility toggle has a tooltip', (tester) async {
      await pumpPanel(tester, existing: existingHost());
      expect(editable(tester, 'host-password-field').obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(editable(tester, 'host-password-field').obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });
  });

  group('validation', () {
    // Sections scrolled out of view must still validate: Save and Enter sit
    // far from the session template at 900x600.
    for (final via in ['Save', 'Enter in the label']) {
      testWidgets('$via at 900x600 validates the off-screen template', (
        tester,
      ) async {
        await pumpPanel(
          tester,
          existing: Host(
            id: 'target-id',
            label: 'srv',
            host: '1.2.3.4',
            username: 'root',
            envVars: {'FOO': 'bar'},
          ),
          size: const Size(900, 600),
          asApp: true,
        );
        final list = find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          field('template-font-size-field'),
          300,
          scrollable: list,
        );
        await tester.pumpAndSettle();
        await tester.enterText(field('env-key-0'), 'BAD-NAME');
        await tester.enterText(field('template-font-size-field'), '200');
        await tester.pumpAndSettle();

        // Back to the top: the template is far out of view.
        await tester.drag(list, const Offset(0, 5000));
        await tester.pumpAndSettle();
        expect(field('host-label-field').hitTestable(), findsOneWidget);

        await tester.tap(field('host-label-field'));
        await tester.pump();
        if (via == 'Save') {
          await tester.tap(field('host-save-button'));
        } else {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
        await tester.pumpAndSettle();

        expect(saved, isNull, reason: 'invalid env key and font size');
        expect(closed, 0);
        expect(find.text('A–Z, 0–9, _ only'), findsOneWidget);
        expect(find.text('6–40'), findsOneWidget);
        expect(
          find.text('A–Z, 0–9, _ only').hitTestable(),
          findsOneWidget,
          reason: 'the first error is scrolled into view',
        );
      });
    }

    testWidgets('a private key that no longer exists shows the hint', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        existing: Host(
          id: 'target-id',
          label: 'srv',
          host: '1.2.3.4',
          username: 'root',
          authType: AuthType.privateKey,
          keyId: 'deleted-key',
        ),
      );
      expect(tester.takeException(), isNull, reason: 'no select assert');
      expect(field('auth-key-select'), findsOneWidget);
      expect(editable(tester, 'auth-key-select').controller.text, isEmpty);
      expect(
        find.descendant(
          of: field('auth-key-select'),
          matching: find.text('Select key'),
        ),
        findsOneWidget,
      );
    });
  });

  group('900x600 overflow', () {
    final bastion = Host(
      id: 'bastion-id',
      label: '$long60-bastion',
      host: '$long60.example.internal',
      username: long60,
    );

    Host longHost({HostProtocol protocol = HostProtocol.ssh}) => Host(
      id: 'long-id',
      label: long60,
      host: '$long60.example.internal',
      port: protocol.defaultPort,
      username: long60,
      group: long60,
      tags: ['env:$long60', 'role:db'],
      protocol: protocol,
      domain: protocol == HostProtocol.rdp ? long60 : null,
      agentForwarding: protocol == HostProtocol.ssh,
      jumpHostIds: const ['bastion-id'],
      workingDir: '/srv/$long60',
      envVars: {'A_${long60.toUpperCase()}': long60},
      startupSnippet: long60,
    );

    /// Scrolls the form to the end, checking for layout errors on the way.
    Future<void> scrollThrough(WidgetTester tester) async {
      // The form's ListView (fields have their own inner Scrollables).
      final list = find
          .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
          .first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }

    for (final protocol in HostProtocol.values) {
      testWidgets('${protocol.name} host with a 60-char label', (tester) async {
        await pumpPanel(
          tester,
          existing: longHost(protocol: protocol),
          others: [bastion],
          size: const Size(900, 600),
          asApp: true,
        );
        expect(tester.takeException(), isNull);
        expect(
          field('host-save-button').hitTestable(),
          findsOneWidget,
          reason: 'the footer stays in view',
        );
        await scrollThrough(tester);
        // Reached the last section without a layout error.
        expect(
          field(
            protocol == HostProtocol.ssh
                ? 'template-tmux-select'
                : 'ssh-tunnel-select',
          ).hitTestable(),
          findsOneWidget,
        );
      });
    }

    testWidgets('new host (scan button, no Delete) at 900x600', (tester) async {
      await pumpPanel(tester, size: const Size(900, 600), asApp: true);
      await tester.enterText(field('host-label-field'), long60);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await scrollThrough(tester);
      expect(field('template-tmux-select').hitTestable(), findsOneWidget);
    });

    testWidgets('a long test error stays inside the panel', (tester) async {
      final error = List.filled(40, 'connection refused').join(' ');
      await pumpPanel(
        tester,
        existing: longHost(),
        others: [bastion],
        size: const Size(900, 600),
        asApp: true,
        ssh: _FakeSsh(StorageService(), (
          success: false,
          latencyMs: 0,
          error: error,
        )),
      );
      await tester.tap(field('host-test-button'));
      await tester.pumpAndSettle();
      expect(find.textContaining('connection refused'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(field('host-save-button').hitTestable(), findsOneWidget);
    });
  });
}
