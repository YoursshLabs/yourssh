import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_add_host_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Widget _wrap(
  HostProvider hosts,
  Widget child, {
  _FakeSessionProvider? session,
  List<SshKeyEntry> keys = const [],
}) =>
    MaterialApp(
      theme: buildMobileTheme(),
      builder: ysRootBuilderTouch,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          ChangeNotifierProvider<KeyProvider>(create: (_) => _KeysProvider(keys)),
          ChangeNotifierProvider<SessionProvider>.value(
            value: session ?? _FakeSessionProvider(),
          ),
        ],
        child: child,
      ),
    );

EditableText _editable(WidgetTester t, Finder field) => t.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('new-host mode shows "New host" title and Save button',
      (tester) async {
    final hosts = HostProvider(StorageService());
    await tester.pumpWidget(_wrap(hosts, const MobileAddHostScreen()));
    await tester.pumpAndSettle();

    expect(find.text('New host'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('edit mode prefills nickname, hostname, port', (tester) async {
    final hosts = HostProvider(StorageService());
    final existing = Host(
      label: 'prod-web',
      host: '10.0.0.5',
      port: 2222,
      username: 'ubuntu',
      tags: const ['prod'],
    );
    await hosts.addHost(existing);

    await tester.pumpWidget(
        _wrap(hosts, MobileAddHostScreen(existing: existing)));
    await tester.pumpAndSettle();

    // Title should say "Edit host"
    expect(find.text('Edit host'), findsOneWidget);

    // Nickname / hostname / port prefilled
    expect(find.widgetWithText(FTextField, 'prod-web'), findsOneWidget);
    expect(find.widgetWithText(FTextField, '10.0.0.5'), findsOneWidget);
    expect(find.widgetWithText(FTextField, '2222'), findsOneWidget);
  });

  testWidgets('tapping Save in new mode calls provider.addHost', (tester) async {
    bool addCalled = false;
    final hosts = _FakeHostProvider(onAdd: () => addCalled = true);
    await tester.pumpWidget(_wrap(hosts, const MobileAddHostScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('host-label')), 'my-box');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('host-address')), '192.168.1.1');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('host-username')), 'admin');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(addCalled, isTrue);
  });

  testWidgets('tapping Save in edit mode calls provider.updateHost',
      (tester) async {
    bool updateCalled = false;
    final existing = Host(
      label: 'old',
      host: '1.2.3.4',
      port: 22,
      username: 'root',
    );
    final hosts = _FakeHostProvider(
      initialHost: existing,
      onUpdate: () => updateCalled = true,
    );

    await tester.pumpWidget(
        _wrap(hosts, MobileAddHostScreen(existing: existing)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('host-label')), 'new-name');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(updateCalled, isTrue);
  });

  testWidgets('edit preserves id, tags, jump chain when saving', (tester) async {
    final hosts = HostProvider(StorageService());
    final existing = Host(
      label: 'Bastion',
      host: '10.0.0.3',
      port: 22,
      username: 'user',
      tags: const ['infra', 'prod'],
      jumpHostIds: ['jump-1', 'jump-2'],
    );
    await hosts.addHost(existing);

    await tester.pumpWidget(
        _wrap(hosts, MobileAddHostScreen(existing: existing)));
    await tester.pumpAndSettle();

    // Change the label only
    await tester.enterText(find.byKey(const Key('host-label')), 'Bastion 2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(hosts.allHosts.length, 1);
    final updated = hosts.allHosts.single;
    expect(updated.id, existing.id);
    expect(updated.label, 'Bastion 2');
    expect(updated.tags, containsAll(['infra', 'prod']));
    expect(updated.jumpHostIds, ['jump-1', 'jump-2']);
  });

  testWidgets('editing cert host preserves authType and shows read-only note',
      (tester) async {
    final hosts = HostProvider(StorageService());
    final cert = Host(
      label: 'Cert Box',
      host: '10.0.0.7',
      username: 'deploy',
      authType: AuthType.certificate,
      keyId: 'key-1',
    );
    await hosts.addHost(cert);

    await tester.pumpWidget(
        _wrap(hosts, MobileAddHostScreen(existing: cert)));
    await tester.pumpAndSettle();

    // Auth note is shown — no password field
    expect(find.text('Certificate authentication'), findsOneWidget);
    expect(find.byKey(const Key('host-password')), findsNothing);

    await tester.enterText(find.byKey(const Key('host-label')), 'Cert Box 2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = hosts.allHosts.single;
    expect(updated.label, 'Cert Box 2');
    expect(updated.authType, AuthType.certificate);
    expect(updated.keyId, 'key-1');
  });

  testWidgets('Group field maps to/from host tags', (tester) async {
    final hosts = HostProvider(StorageService());
    final existing = Host(
      label: 'db-01',
      host: '10.0.0.9',
      username: 'admin',
      tags: const ['staging'],
    );
    await hosts.addHost(existing);

    await tester.pumpWidget(
        _wrap(hosts, MobileAddHostScreen(existing: existing)));
    await tester.pumpAndSettle();

    // The Group field should be prefilled with the first tag
    final groupField = find.byKey(const Key('host-group'));
    expect(groupField, findsOneWidget);
    expect(
        _editable(tester, groupField).controller.text, 'staging');
  });

  testWidgets('Run-on-connect field maps to startupSnippet', (tester) async {
    final hosts = HostProvider(StorageService());
    final existing = Host(
      label: 'dev-box',
      host: '10.0.0.10',
      username: 'dev',
      startupSnippet: 'tmux attach',
    );
    await hosts.addHost(existing);

    await tester.pumpWidget(
        _wrap(hosts, MobileAddHostScreen(existing: existing)));
    await tester.pumpAndSettle();

    final snippetField = find.byKey(const Key('host-startup-snippet'));
    expect(snippetField, findsOneWidget);
    expect(_editable(tester, snippetField).controller.text, 'tmux attach');
  });

  // The app lock lives in Settings -> Security, not in the per-host form.

  testWidgets('host form has no app-lock / biometric switch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final hosts = HostProvider(StorageService());
    await tester.pumpWidget(_wrap(hosts, const MobileAddHostScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(FSwitch), findsNothing);
    expect(find.text('Unlock with biometrics'), findsNothing);
  });

  // ── Fix 2: "Save & connect" wires connectAny; plain "Save" does not ─────

  testWidgets('Save & connect calls connectAny; plain Save does not',
      (tester) async {
    final session = _FakeSessionProvider();
    final hosts = _FakeHostProvider(onAdd: () {});
    await tester.pumpWidget(
      _wrap(hosts, const MobileAddHostScreen(), session: session),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('host-label')), 'box');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('host-address')), '10.0.0.1');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('host-username')), 'root');
    await tester.pump();

    // Tap plain "Save" — connectAny must NOT be called.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(session.connectAnyCalled, isFalse);
    expect(session.connectedHost, isNull);
  });

  testWidgets('Save & connect button calls connectAny with saved host',
      (tester) async {
    final session = _FakeSessionProvider();
    final hosts = _FakeHostProvider(onAdd: () {});
    await tester.pumpWidget(
      _wrap(hosts, const MobileAddHostScreen(), session: session),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('host-label')), 'prod');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('host-address')), '10.0.0.2');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('host-username')), 'ubuntu');
    await tester.pump();

    // Drag the ListView down to reveal the "Save & connect" button at the bottom.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & connect'));
    await tester.pumpAndSettle();

    expect(session.connectAnyCalled, isTrue);
    expect(session.connectedHost?.label, 'prod');
    expect(session.connectedHost?.host, '10.0.0.2');

    // The host passed to connectAny must be the one that was actually saved —
    // id lookup must not rely on allHosts.last.
    final savedHost = hosts.lastAdded;
    expect(savedHost, isNotNull, reason: 'addHost was not called');
    expect(session.connectedHost?.id, savedHost!.id,
        reason: 'connectAny received a different host than the one saved');
  });

  group('port validation (P28)', () {
    Future<_FakeHostProvider> fill(WidgetTester tester, String port,
        {_FakeSessionProvider? session}) async {
      final hosts = _FakeHostProvider(onAdd: () {});
      await tester.pumpWidget(
          _wrap(hosts, const MobileAddHostScreen(), session: session));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('host-label')), 'b');
      await tester.enterText(find.byKey(const Key('host-address')), '1.1.1.1');
      await tester.enterText(find.byKey(const Key('host-username')), 'u');
      await tester.enterText(find.byKey(const Key('host-port')), port);
      await tester.pumpAndSettle();
      return hosts;
    }

    for (final bad in ['0', '65536', '70000']) {
      testWidgets('port $bad is rejected: error shown, no save, no connect',
          (tester) async {
        final session = _FakeSessionProvider();
        final hosts = await fill(tester, bad, session: session);
        expect(find.text('Invalid (1–65535)'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save & connect'));
        await tester.tap(find.text('Save & connect'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(hosts.lastAdded, isNull);
        expect(session.connectAnyCalled, isFalse);
        expect(find.byType(MobileAddHostScreen), findsOneWidget);
      });
    }

    for (final ok in ['1', '65535']) {
      testWidgets('port $ok saves', (tester) async {
        final hosts = await fill(tester, ok);
        expect(find.text('Invalid (1–65535)'), findsNothing);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(hosts.lastAdded?.port, int.parse(ok));
      });
    }

    testWidgets('empty port saves as 22', (tester) async {
      final hosts = await fill(tester, '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(hosts.lastAdded?.port, 22);
    });
  });

  group('forui form behaviour', () {
    testWidgets('360x640 with 60-char nickname/hostname: no overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hosts = HostProvider(StorageService());
      final existing = Host(
        label: 'x' * 60,
        host: 'h' * 60,
        username: 'u' * 60,
        tags: ['g' * 60],
        startupSnippet: 's' * 60,
      );
      await hosts.addHost(existing);
      await tester.pumpWidget(
          _wrap(hosts, MobileAddHostScreen(existing: existing)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('header + primary actions are >=44 px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          _wrap(HostProvider(StorageService()), const MobileAddHostScreen()));
      await tester.pumpAndSettle();
      for (final label in ['Hosts', 'Save', 'Password', 'SSH key']) {
        final b = find.widgetWithText(FButton, label);
        expect(b, findsOneWidget, reason: label);
        expect(tester.getSize(b).height, greaterThanOrEqualTo(44),
            reason: '$label height');
        expect(tester.getSize(b).width, greaterThanOrEqualTo(44),
            reason: '$label width');
      }
      for (final k in ['host-label', 'host-address', 'host-port',
          'host-username', 'host-password']) {
        expect(tester.getSize(find.byKey(Key(k))).height,
            greaterThanOrEqualTo(44), reason: k);
      }
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final sc = find.widgetWithText(FButton, 'Save & connect');
      expect(tester.getSize(sc).height, greaterThanOrEqualTo(44));
    });

    testWidgets('password is obscured and has no reveal toggle',
        (tester) async {
      await tester.pumpWidget(
          _wrap(HostProvider(StorageService()), const MobileAddHostScreen()));
      await tester.pumpAndSettle();
      final pw = find.byKey(const Key('host-password'));
      expect(_editable(tester, pw).obscureText, isTrue);
      expect(_editable(tester, find.byKey(const Key('host-label'))).obscureText,
          isFalse);
      expect(
        find.descendant(of: pw, matching: find.byType(FButton)),
        findsNothing,
        reason: 'no reveal-password toggle (the form never had one)',
      );
      await tester.enterText(pw, 'hunter2');
      await tester.pump();
      expect(_editable(tester, pw).obscureText, isTrue);
    });

    testWidgets('Save stays inert until nickname, hostname and username are '
        'filled', (tester) async {
      var added = false;
      final hosts = _FakeHostProvider(onAdd: () => added = true);
      await tester.pumpWidget(_wrap(hosts, const MobileAddHostScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(added, isFalse);
      expect(find.byType(MobileAddHostScreen), findsOneWidget);
      expect(
          tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
          isNull);
    });

    testWidgets('Next on a field moves focus down the form in order',
        (tester) async {
      await tester.pumpWidget(
          _wrap(HostProvider(StorageService()), const MobileAddHostScreen()));
      await tester.pumpAndSettle();
      bool focused(String k) =>
          _editable(tester, find.byKey(Key(k))).focusNode.hasFocus;
      await tester.tap(find.byKey(const Key('host-label')));
      await tester.pump();
      expect(focused('host-label'), isTrue);
      for (final next in ['host-address', 'host-port', 'host-username']) {
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();
        expect(focused(next), isTrue, reason: 'focus moved to $next');
      }
    });

    testWidgets('Hosts (back) cancels without saving', (tester) async {
      var added = false;
      final hosts = _FakeHostProvider(onAdd: () => added = true);
      await tester.pumpWidget(
        MaterialApp(
          builder: ysRootBuilderTouch,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => MultiProvider(
                      providers: [
                        ChangeNotifierProvider<HostProvider>.value(value: hosts),
                        ChangeNotifierProvider<KeyProvider>(create: (_) => _KeysProvider(const [])),
                        ChangeNotifierProvider<SessionProvider>.value(
                            value: _FakeSessionProvider()),
                      ],
                      child: const MobileAddHostScreen(),
                    ),
                  )),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('New host'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('host-label')), 'draft');
      await tester.tap(find.widgetWithText(FButton, 'Hosts'));
      await tester.pumpAndSettle();
      expect(find.text('New host'), findsNothing);
      expect(added, isFalse);
    });

    testWidgets('SSH key method picks a key and saves privateKey auth',
        (tester) async {
      final key = SshKeyEntry(
        label: 'work-key',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'pub',
        privateKeyPath: 'embedded',
      );
      final hosts = _FakeHostProvider(onAdd: () {});
      await tester.pumpWidget(
          _wrap(hosts, const MobileAddHostScreen(), keys: [key]));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('host-label')), 'k');
      await tester.enterText(find.byKey(const Key('host-address')), '1.1.1.1');
      await tester.enterText(find.byKey(const Key('host-username')), 'root');
      await tester.tap(find.widgetWithText(FButton, 'SSH key'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('host-password')), findsNothing);
      expect(find.bySubtype<FSelect<String>>(), findsOneWidget);
      await tester.tap(find.bySubtype<FSelect<String>>());
      await tester.pumpAndSettle();
      await tester.tap(find.text('work-key').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(hosts.lastAdded?.authType, AuthType.privateKey);
      expect(hosts.lastAdded?.keyId, key.id);
    });

    testWidgets('keys with identical labels are all selectable by their id',
        (tester) async {
      final k1 = SshKeyEntry(
          id: 'aaaaaaaa-111111',
          label: 'dup',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'p',
          privateKeyPath: 'embedded');
      final k2 = SshKeyEntry(
          id: 'bbbbbbbb-222222',
          label: 'dup',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'p',
          privateKeyPath: 'embedded');
      final hosts = _FakeHostProvider(onAdd: () {});
      await tester.pumpWidget(
          _wrap(hosts, const MobileAddHostScreen(), keys: [k1, k2]));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('host-label')), 'k');
      await tester.enterText(find.byKey(const Key('host-address')), '1.1.1.1');
      await tester.enterText(find.byKey(const Key('host-username')), 'root');
      await tester.tap(find.widgetWithText(FButton, 'SSH key'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySubtype<FSelect<String>>());
      await tester.pumpAndSettle();
      expect(find.textContaining('dup (…'), findsNWidgets(2));
      await tester.tap(find.textContaining('dup (…222222').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(hosts.lastAdded?.keyId, k2.id);
    });

    testWidgets('SSH key method is unavailable without keys; Password field '
        'stays', (tester) async {
      await tester.pumpWidget(
          _wrap(HostProvider(StorageService()), const MobileAddHostScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'SSH key'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('host-password')), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake providers
// ---------------------------------------------------------------------------

class _FakeHostProvider extends HostProvider {
  final VoidCallback? onAdd;
  final VoidCallback? onUpdate;

  _FakeHostProvider({Host? initialHost, this.onAdd, this.onUpdate})
      : super(StorageService()) {
    if (initialHost != null) {
      // Seed synchronously so tests don't need to await
      // ignore: invalid_use_of_protected_member
      hosts; // access to init list
      _seedHosts.add(initialHost);
    }
  }

  // We can't easily sync-seed HostProvider (it loads async), so for the
  // fake we override add/update without persisting.
  final List<Host> _seedHosts = [];

  /// The most recently added host — used to verify connectAny received the
  /// correct host instance (id must match, not just label).
  Host? lastAdded;

  @override
  List<Host> get allHosts => _seedHosts;

  @override
  Host? byId(String id) {
    for (final h in _seedHosts) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  Future<void> addHost(Host host, {String? password}) async {
    _seedHosts.add(host);
    lastAdded = host;
    onAdd?.call();
    notifyListeners();
  }

  @override
  Future<void> updateHost(Host host, {String? password}) async {
    final idx = _seedHosts.indexWhere((h) => h.id == host.id);
    if (idx != -1) _seedHosts[idx] = host;
    onUpdate?.call();
    notifyListeners();
  }
}

/// No ~/.ssh discovery: keys come from the test.
class _KeysProvider extends KeyProvider {
  final List<SshKeyEntry> _seed;
  _KeysProvider(this._seed) : super(discoverSshKeys: false);

  @override
  List<SshKeyEntry> get keys => _seed;
}

class _FakeSessionProvider extends SessionProvider {
  bool connectAnyCalled = false;
  Host? connectedHost;

  _FakeSessionProvider()
      : super(SshService(StorageService()), TabMetadataService());

  @override
  Future<AppSession?> connectAny(Host host,
      {String? initialCommand, String auditSource = 'app'}) async {
    connectAnyCalled = true;
    connectedHost = host;
    return null;
  }
}
