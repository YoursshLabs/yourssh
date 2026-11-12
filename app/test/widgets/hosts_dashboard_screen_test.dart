import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/util/host_sort.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';

import '../helpers/ys_test_app.dart';

/// Records connects instead of dialling, and serves canned sessions.
class _FakeSessions extends SessionProvider {
  _FakeSessions(StorageService s) : super(SshService(s), TabMetadataService());

  final connected = <Host>[];
  List<AppSession> fake = [];

  @override
  List<AppSession> get sessions => fake;

  @override
  Future<AppSession?> connectAny(Host host,
      {String? initialCommand, String auditSource = 'app'}) async {
    connected.add(host);
    return null;
  }
}

class _Env {
  final HostProvider hosts;
  final SettingsProvider settings;
  final _FakeSessions sessions;
  final calls = <String>[];
  final edited = <Host>[];
  _Env(this.hosts, this.settings, this.sessions);
}

final _long60 = List.filled(60, 'w').join();

Future<_Env> _pump(
  WidgetTester t, {
  List<Host> hosts = const [],
  List<String> groups = const [],
  String view = 'grid',
  double sidebar = 200,
  double panel = 0,
  Size size = const Size(1400, 900),
  List<AppSession> Function(List<Host>)? sessions,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final storage = StorageService();
  late HostProvider hp;
  late SettingsProvider settings;
  await t.runAsync(() async {
    hp = HostProvider(storage);
    await hp.ready;
    for (final h in hosts) {
      await hp.addHost(h);
    }
    for (final g in groups) {
      await hp.addGroup(g);
    }
    settings = SettingsProvider();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  settings.dashboardViewMode = view;
  final fake = _FakeSessions(storage);
  if (sessions != null) fake.fake = sessions(hosts);
  final env = _Env(hp, settings, fake);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hp),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<SessionProvider>.value(value: fake),
      ],
      child: ysTestApp(
        Row(
          children: [
            SizedBox(width: sidebar),
            Expanded(
              child: HostsDashboard(
                onAddHost: () => env.calls.add('add'),
                onEditHost: (h) => env.edited.add(h),
                onOpenLocalTerminal: () => env.calls.add('local'),
                onNewGroup: () => env.calls.add('group'),
                onImport: () => env.calls.add('import'),
                onDiscover: () => env.calls.add('discover'),
              ),
            ),
            if (panel > 0) SizedBox(width: panel),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return env;
}

Finder _card(Host h) => find.byKey(ValueKey('host-card-${h.id}'));

/// The card's More button (focus can keep another card's actions visible).
Finder _more(Host h) =>
    find.descendant(of: _card(h), matching: find.byTooltip('More'));

TestGesture? _mouse;

/// Moves one shared mouse pointer (added once per test) over [f].
Future<void> _hover(WidgetTester t, Finder f) async {
  if (_mouse == null) {
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    _mouse = g;
    addTearDown(() async {
      await g.removePointer();
      _mouse = null;
    });
  }
  await _mouse!.moveTo(t.getCenter(f));
  await t.pumpAndSettle();
}

/// Buttons inside a host card wait out the card's double-tap window.
Future<void> _tapInCard(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await t.pumpAndSettle();
}

FocusNode _cardFocus(WidgetTester t, Host h) => Focus.of(t.element(
    find.descendant(
        of: _card(h), matching: find.byKey(const Key('ys-host-card-box')))));

void main() {
  final web = Host(
      label: 'web', host: '10.0.0.1', username: 'root', group: 'prod',
      tags: ['env:prod']);
  final db = Host(label: 'db', host: '10.0.0.2', username: 'pg', port: 2222);
  final win = Host(
      label: 'win',
      host: '10.0.0.3',
      username: 'Administrator',
      port: 3389,
      protocol: HostProtocol.rdp);

  group('top bar actions', () {
    testWidgets('every top-bar action is present and wired', (t) async {
      final env = await _pump(t, hosts: [web, db]);

      expect(find.text('Search hosts, IPs, or tags...'), findsOneWidget);
      expect(find.text(HostSortMode.nameAsc.label), findsOneWidget);
      expect(find.byTooltip('Grid view'), findsOneWidget);
      expect(find.byTooltip('List view'), findsOneWidget);

      await t.tap(find.text('Discover'));
      await t.tap(find.text('Local terminal'));
      await t.tap(find.text('New host'));
      await t.pumpAndSettle();
      expect(env.calls, ['discover', 'local', 'add']);

      await t.tap(find.byTooltip('Show menu'));
      await t.pumpAndSettle();
      expect(find.text('New Group'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      await t.tap(find.text('New Group'));
      await t.pumpAndSettle();
      expect(find.text('Import'), findsNothing, reason: 'menu closes');
      await t.tap(find.byTooltip('Show menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Import'));
      await t.pumpAndSettle();
      expect(env.calls, ['discover', 'local', 'add', 'group', 'import']);

      await t.tap(find.text('Select'));
      await t.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
    });

    testWidgets('search filters and shows "x of N hosts"', (t) async {
      await _pump(t, hosts: [web, db]);
      expect(find.text('2 of 2 hosts'), findsOneWidget);
      await t.enterText(
          find.descendant(
              of: find.byKey(const Key('hosts-search')),
              matching: find.byType(EditableText)),
          'web');
      await t.pumpAndSettle();
      expect(find.text('1 of 2 hosts'), findsOneWidget);
      expect(find.text('db'), findsNothing);
    });

    testWidgets('facet chip toggles the filter', (t) async {
      await _pump(t, hosts: [web, db]);
      // The search field and the host card's tag show the same text.
      await t.tap(find.byKey(const ValueKey('facet-env:prod')));
      await t.pumpAndSettle();
      expect(find.text('1 of 2 hosts'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('facet-env:prod')));
      await t.pumpAndSettle();
      expect(find.text('2 of 2 hosts'), findsOneWidget);
    });

    testWidgets('sort menu and view toggle persist to settings', (t) async {
      final env = await _pump(t, hosts: [web, db]);
      await t.tap(find.text(HostSortMode.nameAsc.label));
      await t.pumpAndSettle();
      await t.tap(find.text(HostSortMode.createdDesc.label));
      await t.pumpAndSettle();
      expect(env.settings.dashboardSort, HostSortMode.createdDesc.key);

      await t.tap(find.byTooltip('List view'));
      await t.pumpAndSettle();
      expect(env.settings.dashboardViewMode, 'list');
    });

    testWidgets('empty state offers New host', (t) async {
      final env = await _pump(t);
      expect(find.text('No hosts yet'), findsOneWidget);
      // Top bar + empty state.
      expect(find.text('New host'), findsNWidgets(2));
      await t.tap(find.text('New host').last);
      await t.pumpAndSettle();
      expect(env.calls, ['add']);
    });
  });

  group('groups', () {
    testWidgets('group cards show name and count; empty pinned group can be '
        'deleted', (t) async {
      final env = await _pump(t, hosts: [web, db], groups: ['Empty']);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('PROD'), findsOneWidget);
      expect(find.text('EMPTY'), findsOneWidget);
      expect(find.text('0 hosts'), findsOneWidget);

      await _hover(t, find.text('EMPTY'));
      await t.tap(find.byTooltip('Group options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete group'));
      await t.pumpAndSettle();
      expect(env.hosts.pinnedGroups, isEmpty);
      expect(find.text('EMPTY'), findsNothing);
    });

    testWidgets('a group with hosts has no delete menu', (t) async {
      await _pump(t, hosts: [web]);
      await _hover(t, find.text('PROD'));
      expect(find.byTooltip('Group options'), findsNothing);
    });
  });

  group('host card actions', () {
    testWidgets('SSH card: hover actions and every context-menu item',
        (t) async {
      final env = await _pump(t, hosts: [web]);
      await _hover(t, _card(web));
      expect(find.byTooltip('Test Connection'), findsOneWidget);
      expect(find.byTooltip('SFTP'), findsOneWidget);
      expect(find.byTooltip('Monitor'), findsNothing,
          reason: 'no open SSH session');
      await _tapInCard(t, find.byTooltip('More'));
      for (final item in [
        'Connect',
        'SFTP',
        'Monitor',
        'Edit',
        'Duplicate',
        'Copy SSH URL',
        'Move to Group',
        'Export',
        'Delete',
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(env.edited.single.id, web.id);
      expect(find.text('Duplicate'), findsNothing, reason: 'menu closes');
    });

    testWidgets('menu Connect and Delete act on the host', (t) async {
      final env = await _pump(t, hosts: [web, db]);
      await _hover(t, _card(web));
      await _tapInCard(t, _more(web));
      await t.tap(find.text('Connect'));
      await t.pumpAndSettle();
      expect(env.sessions.connected.single.id, web.id);

      await _hover(t, _card(db));
      await _tapInCard(t, _more(db));
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(env.hosts.allHosts.map((h) => h.id), [web.id]);
    });

    testWidgets('RDP card hides SSH-only actions and copies an rdp:// URL',
        (t) async {
      String? clip;
      t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await _pump(t, hosts: [win]);
      expect(find.text('RDP'), findsOneWidget);
      await _hover(t, _card(win));
      expect(find.byTooltip('Test Connection'), findsNothing);
      expect(find.byTooltip('SFTP'), findsNothing);
      await _tapInCard(t, find.byTooltip('More'));
      expect(find.text('SFTP'), findsNothing);
      expect(find.text('Monitor'), findsNothing);
      await t.tap(find.text('Copy RDP URL'));
      await t.pumpAndSettle();
      expect(clip, 'rdp://Administrator@10.0.0.3:3389');
      expect(find.text('RDP URL copied'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
    });

    testWidgets('open sessions: count on the card, Monitor on hover',
        (t) async {
      await _pump(t, hosts: [web, db], sessions: (hosts) => [
            SshSession(host: hosts[0], status: SessionStatus.connected),
            SshSession(host: hosts[0]),
          ]);
      expect(find.text('2 sessions'), findsOneWidget);
      await _hover(t, _card(web));
      expect(find.byTooltip('Monitor'), findsOneWidget);
    });

    testWidgets('Move to Group dialog moves the host', (t) async {
      final env = await _pump(t, hosts: [web, db]);
      await _hover(t, _card(db));
      await _tapInCard(t, _more(db));
      await t.tap(find.text('Move to Group'));
      await t.pumpAndSettle();
      expect(find.text('No group'), findsOneWidget);
      await t.tap(find.text('prod'));
      await t.pumpAndSettle();
      expect(env.hosts.allHosts.firstWhere((h) => h.id == db.id).group, 'prod');
    });

    testWidgets('Export dialog shows ssh config and JSON', (t) async {
      await _pump(t, hosts: [db]);
      await _hover(t, _card(db));
      await _tapInCard(t, _more(db));
      await t.tap(find.text('Export'));
      await t.pumpAndSettle();
      expect(find.text('Export Host'), findsOneWidget);
      expect(find.textContaining('HostName 10.0.0.2'), findsOneWidget);
      await t.tap(find.text('JSON'));
      await t.pumpAndSettle();
      expect(find.textContaining('"host": "10.0.0.2"'), findsOneWidget);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      expect(find.text('Export Host'), findsNothing);
    });
  });

  group('keyboard', () {
    testWidgets('double-click connects; Enter on a focused card does the same',
        (t) async {
      final env = await _pump(t, hosts: [web]);
      await t.tap(_card(web));
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(_card(web));
      await t.pumpAndSettle();
      expect(env.sessions.connected.map((h) => h.id), [web.id]);

      final node = _cardFocus(t, web);
      node.requestFocus();
      await t.pump();
      expect(node.hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(env.sessions.connected.map((h) => h.id), [web.id, web.id]);
    });

    testWidgets('select mode: click and Enter toggle the same way; '
        'Escape exits', (t) async {
      final env = await _pump(t, hosts: [web, db]);
      await t.tap(find.text('Select'));
      await t.pumpAndSettle();

      await t.tap(_card(web));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(env.sessions.connected, isEmpty);

      final node = _cardFocus(t, db);
      node.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(env.sessions.connected, isEmpty, reason: 'Enter selects only');

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('1 selected'), findsNothing);
    });
  });

  group('900x600 overflow', () {
    final long = Host(
      label: _long60,
      host: '$_long60.example.internal',
      username: _long60,
      port: 2222,
      group: _long60,
      tags: ['env:$_long60', 'role:db', 'team:platform'],
    );
    final longRdp = Host(
      label: '$_long60-rdp',
      host: '10.0.0.9',
      username: _long60,
      port: 3389,
      protocol: HostProtocol.rdp,
    );

    for (final view in ['grid', 'list']) {
      testWidgets('$view view with a 60-char label', (t) async {
        await _pump(t,
            hosts: [long, longRdp, web],
            view: view,
            size: const Size(900, 600),
            sessions: (hosts) => [SshSession(host: hosts[0])]);
        expect(t.takeException(), isNull);
        await _hover(t, _card(long));
        expect(t.takeException(), isNull);
        expect(find.byTooltip('More'), findsOneWidget);
      });

      testWidgets('$view view with the host panel open (360 px)', (t) async {
        await _pump(t,
            hosts: [long, longRdp],
            view: view,
            size: const Size(900, 600),
            panel: 340);
        expect(t.takeException(), isNull);
        await _hover(t, _card(long));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('select mode at 900x600', (t) async {
      await _pump(t, hosts: [long, longRdp], size: const Size(900, 600));
      // Narrow bar: icon-only buttons, labels in tooltips; New host in view.
      expect(find.text('New host').hitTestable(), findsOneWidget);
      await t.tap(find.byTooltip('Select'));
      await t.pumpAndSettle();
      await t.tap(_card(long));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
