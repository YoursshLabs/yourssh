import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_add_host_screen.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
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
}) =>
    MaterialApp(
      theme: buildMobileTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          ChangeNotifierProvider(create: (_) => KeyProvider()),
          ChangeNotifierProvider<SessionProvider>.value(
            value: session ?? _FakeSessionProvider(),
          ),
        ],
        child: child,
      ),
    );

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
    expect(find.widgetWithText(TextField, 'prod-web'), findsOneWidget);
    expect(find.widgetWithText(TextField, '10.0.0.5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2222'), findsOneWidget);
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
        tester.widget<TextField>(groupField).controller?.text ?? '', 'staging');
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
    expect(tester.widget<TextField>(snippetField).controller?.text ?? '',
        'tmux attach');
  });

  // ── Fix 1: biometric toggle uses the shared kAppLockPrefKey ─────────────

  testWidgets('biometric toggle persists under shared kAppLockPrefKey',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final hosts = HostProvider(StorageService());
    await tester.pumpWidget(_wrap(hosts, const MobileAddHostScreen()));
    await tester.pumpAndSettle();

    // The switch should be present and enabled by default (kAppLockPrefKey
    // absent → defaults to true).
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    // Toggle it off.
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    // Must write under the SHARED key, not a local orphan key.
    expect(prefs.getBool(kAppLockPrefKey), isFalse);
    // The old orphan key must not exist.
    expect(prefs.getBool('yourssh.app_lock_enabled'), isNull);
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
    await tester.drag(find.byType(ListView), const Offset(0, -400));
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

class _FakeSessionProvider extends SessionProvider {
  bool connectAnyCalled = false;
  Host? connectedHost;

  _FakeSessionProvider()
      : super(SshService(StorageService()), TabMetadataService());

  @override
  Future<AppSession?> connectAny(Host host, {String? initialCommand}) async {
    connectAnyCalled = true;
    connectedHost = host;
    return null;
  }
}
