import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilderTouch;
import 'package:yourssh_ui/yourssh_ui.dart';

// Fake SessionProvider with one connected SSH session.
class _FakeSessionProvider extends SessionProvider {
  final SshSession _session;
  _FakeSessionProvider(this._session)
      : super(SshService(StorageService()), TabMetadataService());

  @override
  List<SshSession> get sshSessions => [_session];

  @override
  AppSession? get activeSession => _session;
}

class _MultiProvider extends SessionProvider {
  final List<SshSession> sessions;
  SshSession active;
  final closed = <String>[];
  _MultiProvider(this.sessions)
      : active = sessions.first,
        super(SshService(StorageService()), TabMetadataService());

  @override
  List<SshSession> get sshSessions => List.unmodifiable(sessions);

  @override
  AppSession? get activeSession => active;

  @override
  void setActive(String id) {
    active = sessions.firstWhere((s) => s.id == id);
    notifyListeners();
  }

  @override
  Future<void> closeSession(String id) async {
    closed.add(id);
  }
}

Future<_MultiProvider> _pumpMulti(
  WidgetTester tester, {
  String label = 'web-01',
  void Function(Host)? onFiles,
  void Function(Host)? onPf,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final a = SshSession(
    id: 's1',
    host: Host(id: 'h1', label: label, host: '10.0.4.21', port: 22, username: 'deploy'),
    status: SessionStatus.connected,
  );
  final b = SshSession(
    id: 's2',
    host: Host(id: 'h2', label: 'db-02', host: '10.0.4.22', port: 22, username: 'root'),
    status: SessionStatus.connected,
  );
  final sp = _MultiProvider([a, b]);
  await tester.pumpWidget(MaterialApp(
    builder: ysRootBuilderTouch,
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: sp),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MobileTerminalScreen(onOpenFiles: onFiles, onOpenPortForward: onPf),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return sp;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows session tab label and TerminalView for connected session',
      (tester) async {
    final host = Host(
      id: 'h1',
      label: 'web-01',
      host: '10.0.4.21',
      port: 22,
      username: 'deploy',
    );
    final session = SshSession(
      id: 's1',
      host: host,
      status: SessionStatus.connected,
    );
    final sp = _FakeSessionProvider(session);

    await tester.pumpWidget(MaterialApp(
      builder: ysRootBuilderTouch,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionProvider>.value(value: sp),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MobileTerminalScreen(),
      ),
    ));
    await tester.pump();

    // Session tab label should be visible.
    expect(find.text('web-01'), findsAtLeastNWidgets(1));
    // TerminalView should be present.
    expect(find.byType(TerminalView), findsOneWidget);
  });

  testWidgets('360x640 with a 60-char host label: header and chips do not overflow',
      (tester) async {
    await _pumpMulti(tester, label: 'x' * 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header is an FHeader with back + More actions >= 44 px',
      (tester) async {
    await _pumpMulti(tester);
    expect(find.byWidgetPredicate((w) => w is FHeader), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    final actions = find.byType(FHeaderAction);
    expect(actions, findsNWidgets(2));
    for (final e in actions.evaluate()) {
      final size = tester.getSize(find.byWidget(e.widget));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('menu: Files and Port forwarding call back with the host',
      (tester) async {
    Host? files;
    Host? pf;
    await _pumpMulti(tester, onFiles: (h) => files = h, onPf: (h) => pf = h);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await tester.tap(find.byTooltip('More'));
    await settle();
    expect(find.text('Files'), findsOneWidget);
    await tester.tap(find.text('Files'));
    await settle();
    await settle();
    expect(files?.id, 'h1');
    await tester.tap(find.byTooltip('More'));
    await settle();
    await tester.tap(find.text('Port forwarding'));
    await settle();
    await settle();
    expect(pf?.id, 'h1');
  });

  testWidgets('session chips: tap switches, close closes, all >= 44 px',
      (tester) async {
    final sp = await _pumpMulti(tester);
    for (final m in ['New session', 'Close session']) {
      expect(find.byTooltip(m), findsWidgets, reason: m);
    }
    final chip = find.byKey(const ValueKey('session-chip-s2'));
    expect(chip, findsOneWidget);
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    final close = find.byKey(const ValueKey('session-chip-close-s2'));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
    final add = find.byTooltip('New session');
    expect(tester.getSize(add).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(add).width, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const ValueKey('session-chip-label-s2')));
    await tester.pump();
    expect(sp.active.id, 's2');
    await tester.tap(close);
    await tester.pump();
    expect(sp.closed, ['s2']);
  });

  testWidgets('accessory keys keep the TerminalView focused in the screen',
      (tester) async {
    await _pumpMulti(tester);
    bool termFocused() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      return ctx?.findAncestorWidgetOfExactType<TerminalView>() != null;
    }

    // Focus the terminal by tapping into it.
    await tester.tapAt(const Offset(180, 250));
    await tester.pump(const Duration(milliseconds: 150));
    expect(termFocused(), isTrue, reason: 'terminal should take focus first');
    for (final f in [find.text('Esc'), find.text('Tab'), find.text('Ctrl')]) {
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 150));
      expect(termFocused(), isTrue, reason: 'after $f');
    }
  });
}
