import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/util/host_sort.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';

import 'package:forui/forui.dart' show FButton;
import 'package:yourssh_ui/yourssh_ui.dart' show YsColors;

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

/// Test connection resolves only when the test completes [pending].
class _FakeSsh extends SshService {
  _FakeSsh(super.storage);

  Completer<({bool success, int latencyMs, String? error})>? pending;

  @override
  Future<({bool success, int latencyMs, String? error})> testConnection(
    Host host, {
    String? password,
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
  }) =>
      (pending = Completer()).future;
}

class _Env {
  final HostProvider hosts;
  final SettingsProvider settings;
  final _FakeSessions sessions;
  late final _FakeSsh ssh;
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
  final env = _Env(hp, settings, fake)..ssh = _FakeSsh(storage);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hp),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<SessionProvider>.value(value: fake),
        ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
        Provider<StorageService>.value(value: storage),
        Provider<SshService>.value(value: env.ssh),
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

Color? _dotColor(WidgetTester t, Host h) => (t
        .widget<Container>(find.descendant(
            of: _card(h), matching: find.byKey(const Key('host-status-dot'))))
        .decoration! as BoxDecoration)
    .color;

Future<void> _tab(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.tab);
  await t.pumpAndSettle();
}

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
  final vnc = Host(
      label: 'vnc',
      host: '10.0.0.4',
      username: 'u',
      port: 5900,
      protocol: HostProtocol.vnc);

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
      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      await t.tap(find.text('New group'));
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
      expect(find.byTooltip('Test connection'), findsOneWidget);
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
        'Move to group',
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
      // Delete now asks first (final review fix).
      expect(find.text('Delete host?'), findsOneWidget);
      expect(env.hosts.allHosts, hasLength(2));
      await t.tap(find.widgetWithText(FButton, 'Delete'));
      await t.pumpAndSettle();
      expect(env.hosts.allHosts.map((h) => h.id), [web.id]);
    });

    Future<_Env> openDeleteConfirm(WidgetTester t) async {
      final env = await _pump(t, hosts: [web, db]);
      await _hover(t, _card(db));
      await _tapInCard(t, _more(db));
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete host?'), findsOneWidget);
      return env;
    }

    testWidgets('menu Delete: Cancel keeps the host', (t) async {
      final env = await openDeleteConfirm(t);
      await t.tap(find.widgetWithText(FButton, 'Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Delete host?'), findsNothing);
      expect(env.hosts.allHosts, hasLength(2));
    });

    testWidgets('menu Delete: Escape keeps the host', (t) async {
      final env = await openDeleteConfirm(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Delete host?'), findsNothing);
      expect(env.hosts.allHosts, hasLength(2));
    });

    testWidgets('menu Delete: Enter on the default (Cancel) keeps the host',
        (t) async {
      final env = await openDeleteConfirm(t);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Delete host?'), findsNothing);
      expect(env.hosts.allHosts, hasLength(2));
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
      expect(find.byTooltip('Test connection'), findsNothing);
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
      await t.tap(find.text('Move to group'));
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
      expect(find.text('Export host'), findsOneWidget);
      expect(find.textContaining('HostName 10.0.0.2'), findsOneWidget);
      await t.tap(find.text('JSON'));
      await t.pumpAndSettle();
      expect(find.textContaining('"host": "10.0.0.2"'), findsOneWidget);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      expect(find.text('Export host'), findsNothing);
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

  group('fix round 1', () {
    testWidgets('status dot: green only for a connected SSH session',
        (t) async {
      await _pump(t, hosts: [web, db, win], sessions: (hosts) => [
            SshSession(host: hosts[0], status: SessionStatus.connected),
            SshSession(host: hosts[1]), // connecting
          ]);
      expect(_dotColor(t, web), YsColors.ok);
      expect(_dotColor(t, db), isNot(YsColors.ok));
      expect(_dotColor(t, win), isNot(YsColors.ok));
    });

    testWidgets('Tab from the search field reaches the first host card',
        (t) async {
      await _pump(t, hosts: [web, db]);
      await t.tap(find.byKey(const Key('hosts-search')));
      await t.pumpAndSettle();
      // Sorted A→Z, so db is the first card.
      final first = _cardFocus(t, db);
      final second = _cardFocus(t, web);
      var tabs = 0;
      while (!first.hasPrimaryFocus && tabs < 30) {
        expect(second.hasPrimaryFocus, isFalse,
            reason: 'reached the second card before the first');
        await _tab(t);
        tabs++;
      }
      expect(first.hasPrimaryFocus, isTrue, reason: 'after $tabs tabs');
    });

    testWidgets('select mode: a checkbox tap toggles exactly once; the '
        'checkbox is not a tab stop', (t) async {
      await _pump(t, hosts: [web, db]);
      await t.tap(find.text('Select'));
      await t.pumpAndSettle();
      final box = find.descendant(
          of: _card(web), matching: find.byKey(const Key('host-card-checkbox')));
      await t.tap(box);
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(box);
      await t.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);

      _cardFocus(t, db).requestFocus();
      await t.pumpAndSettle();
      await _tab(t);
      expect(_cardFocus(t, web).hasPrimaryFocus, isTrue,
          reason: 'one tab stop per card');
    });

    testWidgets('VNC card: SSH-only actions hidden, copies a vnc:// URL',
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

      await _pump(t, hosts: [vnc]);
      expect(find.text('VNC'), findsOneWidget);
      await _hover(t, _card(vnc));
      expect(find.byTooltip('Test connection'), findsNothing);
      expect(find.byTooltip('SFTP'), findsNothing);
      await _tapInCard(t, _more(vnc));
      expect(find.text('SFTP'), findsNothing);
      expect(find.text('Monitor'), findsNothing);
      expect(find.text('Connect'), findsOneWidget);
      await t.tap(find.text('Copy VNC URL'));
      await t.pumpAndSettle();
      expect(clip, 'vnc://u@10.0.0.4:5900');
      expect(find.text('VNC URL copied'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
    });

    testWidgets('keyboard Test keeps focus on the card while it runs',
        (t) async {
      final agentHost = Host(
          label: 'agent', host: '10.0.0.7', username: 'u',
          authType: AuthType.agent);
      final env = await _pump(t, hosts: [agentHost]);
      final card = _cardFocus(t, agentHost);
      card.requestFocus();
      await t.pumpAndSettle();
      expect(find.byTooltip('Test connection'), findsOneWidget,
          reason: 'actions show while the card has focus');
      await _tab(t); // into the card's first action: Test connection
      expect(card.hasPrimaryFocus, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(env.ssh.pending, isNotNull, reason: 'Test started');
      expect(find.byTooltip('Test connection'), findsNothing,
          reason: 'spinner replaces the actions');
      expect(card.hasPrimaryFocus, isTrue, reason: 'focus moved to the card');

      env.ssh.pending!.complete((success: true, latencyMs: 12, error: null));
      await t.pump();
      expect(find.text('12ms'), findsOneWidget);
      expect(card.hasPrimaryFocus, isTrue);
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
      expect(find.byTooltip('Test connection'), findsOneWidget);
      expect(card.hasFocus, isTrue);
    });

    testWidgets('group menu: hidden button is not hit-testable or focusable; '
        'card focus reveals it and Tab reaches it', (t) async {
      await _pump(t, hosts: [web], groups: ['Empty']);
      expect(find.byTooltip('Group options').hitTestable(), findsNothing);

      // Tab from the search field: the hidden button is never a stop.
      final groupCard = Focus.of(t.element(find.text('EMPTY')));
      await t.tap(find.byKey(const Key('hosts-search')));
      await t.pumpAndSettle();
      var tabs = 0;
      while (!groupCard.hasPrimaryFocus && tabs < 30) {
        await _tab(t);
        tabs++;
      }
      expect(groupCard.hasPrimaryFocus, isTrue, reason: 'card is a tab stop');
      expect(find.byTooltip('Group options').hitTestable(), findsOneWidget,
          reason: 'card focus reveals the menu button');
      await _tab(t);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.text('Delete group'), findsOneWidget);
    });

    testWidgets('compact toolbar button announces its name once', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, hosts: [web], size: const Size(900, 600));
      // Count every mention across the whole tree: a Tooltip puts its
      // message on a parent node, apart from the button's own label.
      final spoken = <String>[];
      SemanticsNode? named;
      void visit(SemanticsNode n) {
        for (final text in [n.label, n.tooltip]) {
          if (RegExp(r'\bSelect\b').hasMatch(text)) {
            spoken.add(text);
            named = n;
          }
        }
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }
      visit(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      expect(spoken, ['Select'], reason: 'one accessible name');
      expect(named!.label, 'Select');
      expect(named!.getSemanticsData().flagsCollection.isButton, isTrue,
          reason: 'the name sits on the button node');
      h.dispose();
    });
  });

  group('toolbar fits at the 900x600 minimum', () {
    // Every control that is on screen must lie fully inside the toolbar, with
    // the host panel closed (900 - sidebar) and open (360 px panel).
    final controls = <String, Finder>{
      'search': find.byKey(const Key('hosts-search')),
      'sort': find.byKey(const Key('hosts-sort')),
      'view toggle': find.byKey(const Key('hosts-view-toggle')),
      'discover': find.byKey(const Key('hosts-discover')),
      'select': find.byKey(const Key('hosts-select')),
      'local terminal': find.byKey(const Key('hosts-local-terminal')),
      'new host split': find.byKey(const Key('hosts-new-split')),
      'more': find.byKey(const Key('hosts-more')),
    };

    void expectInside(WidgetTester t) {
      final bar = t.getRect(find.byKey(const Key('hosts-toolbar')));
      var shown = 0;
      controls.forEach((name, f) {
        if (f.evaluate().isEmpty) return;
        shown++;
        final r = t.getRect(f);
        expect(r.left >= bar.left - 0.5 && r.right <= bar.right + 0.5, isTrue,
            reason: '$name $r is outside the toolbar $bar');
      });
      expect(shown, greaterThanOrEqualTo(3));
      // The primary action is always reachable.
      expect(find.byKey(const Key('hosts-new-split')), findsOneWidget);
      expect(find.byTooltip('Show menu').hitTestable(), findsOneWidget);
    }

    testWidgets('panel closed', (t) async {
      await _pump(t, hosts: [web], size: const Size(900, 600));
      expect(t.takeException(), isNull);
      expectInside(t);
    });

    testWidgets('panel open (340 px)', (t) async {
      await _pump(t, hosts: [web], size: const Size(900, 600), panel: 340);
      expect(t.takeException(), isNull);
      expectInside(t);
    });

    testWidgets('narrow bar keeps sort and view reachable in the More menu',
        (t) async {
      await _pump(t, hosts: [web], size: const Size(900, 600), panel: 340);
      await t.tap(find.byKey(const Key('hosts-more')));
      await t.pumpAndSettle();
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Local terminal'), findsOneWidget);
      expect(find.text('Grid'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      await t.tap(find.text('Newest first'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
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
