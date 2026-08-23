import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/mobile/services/host_reachability_probe.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

// ---------------------------------------------------------------------------
// Fake SessionProvider — injects a pre-built SshSession so connectAny
// immediately materialises a session without real SSH.
// ---------------------------------------------------------------------------

class _FakeSessionProvider extends SessionProvider {
  final List<SshSession> _sessions;
  int connectAnyCalls = 0;

  _FakeSessionProvider(this._sessions)
      : super(SshService(StorageService()), TabMetadataService());

  @override
  List<SshSession> get sshSessions => List.unmodifiable(_sessions);

  /// Mutate the injected list and notify so [didChangeDependencies] fires.
  void setSessions(List<SshSession> updated) {
    _sessions
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  /// Override the real connectAny so no SSH dial happens.
  @override
  Future<AppSession?> connectAny(Host host, {String? initialCommand}) async {
    connectAnyCalls++;
    // The session is already injected; return null like the SSH path does.
    return null;
  }
}

/// Fake whose `connectAny` future stays pending, which is what the real one
/// does: SessionProvider._doConnect awaits SshService.openShell, and that only
/// completes when the shell closes. A caller that awaits it before navigating
/// would sit on the host list for the whole session.
class _PendingSessionProvider extends _FakeSessionProvider {
  _PendingSessionProvider(super.sessions);

  @override
  Future<AppSession?> connectAny(Host host, {String? initialCommand}) {
    connectAnyCalls++;
    // Mirror the real provider: the session is registered synchronously…
    setSessions([..._sessions, SshSession(host: host)]);
    // …while the future itself stays pending until the shell closes.
    return Completer<AppSession?>().future;
  }
}

// ---------------------------------------------------------------------------
// Helper: pumps MobileHostsScreen inside a Navigator with all required
// providers so that navigation to MobileTerminalScreen works in tests.
// ---------------------------------------------------------------------------

Future<({_FakeSessionProvider sp, HostProvider hp})> _pump(
  WidgetTester tester, {
  List<Host> hosts = const [],
  List<SshSession> sessions = const [],
  _FakeSessionProvider Function(List<SshSession>)? provider,
}) async {
  SharedPreferences.setMockInitialValues({});
  final hp = HostProvider(StorageService());
  for (final h in hosts) {
    await hp.addHost(h);
  }

  final sp = (provider ?? _FakeSessionProvider.new)(sessions.toList());
  final probe = HostReachabilityProbe(connector: (_, _, _) async {});
  final settings = SettingsProvider();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hp),
        ChangeNotifierProvider<SessionProvider>.value(value: sp),
        ChangeNotifierProvider<HostReachabilityProbe>.value(value: probe),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: MaterialApp(
        home: const MobileHostsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (sp: sp, hp: hp);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---------------------------------------------------------------------------
  // T1: Tapping a host pushes MobileTerminalScreen
  // ---------------------------------------------------------------------------
  testWidgets('tapping a host pushes MobileTerminalScreen', (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');
    final session = SshSession(host: host);

    await _pump(tester, hosts: [host], sessions: [session]);

    expect(find.byType(HostCard), findsOneWidget);
    await tester.tap(find.byType(HostCard));
    // Use pump with a Duration to avoid pumpAndSettle timing out on xterm's
    // continuous cursor blink animations.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MobileTerminalScreen), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // T1b: The terminal must open while the connection is still live
  // ---------------------------------------------------------------------------
  testWidgets('tapping a host opens the terminal without waiting for the '
      'session to end', (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');

    // No live session yet, so the tap takes the connect path.
    final result = await _pump(
      tester,
      hosts: [host],
      provider: _PendingSessionProvider.new,
    );

    await tester.tap(find.byType(HostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(result.sp.connectAnyCalls, 1);
    expect(find.byType(MobileTerminalScreen), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // T2: Re-tapping a connected host navigates to Terminal without duplicate
  // ---------------------------------------------------------------------------
  testWidgets('re-tapping connected host navigates without extra connect call',
      (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');
    final session = SshSession(host: host);

    // Mark the session as connected so _stateFor returns HostConnState.connected.
    session.status = SessionStatus.connected;

    final result = await _pump(tester, hosts: [host], sessions: [session]);

    await tester.tap(find.byType(HostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // connectAny must NOT have been called (session already live).
    expect(result.sp.connectAnyCalls, 0);
    expect(find.byType(MobileTerminalScreen), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // T3: Popping Terminal returns to Hosts
  // ---------------------------------------------------------------------------
  testWidgets('back button from Terminal returns to Hosts', (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');
    final session = SshSession(host: host);

    await _pump(tester, hosts: [host], sessions: [session]);

    await tester.tap(find.byType(HostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MobileTerminalScreen), findsOneWidget);

    // Tap the back arrow in the terminal header.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MobileHostsScreen), findsOneWidget);
    expect(find.byType(MobileTerminalScreen), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // T4: "+" tile shows a host-picker bottom sheet
  // ---------------------------------------------------------------------------
  testWidgets('+ tile opens host picker bottom sheet', (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');
    final session = SshSession(host: host);

    await _pump(tester, hosts: [host], sessions: [session]);

    // Navigate to the terminal screen first.
    await tester.tap(find.byType(HostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap the "+" tile inside MobileTerminalScreen's session tab strip.
    final addInTerminal = find.descendant(
      of: find.byType(MobileTerminalScreen),
      matching: find.byIcon(Icons.add),
    );
    await tester.tap(addInTerminal);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A bottom sheet should appear with 'Connect to host' heading.
    expect(find.text('Connect to host'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // T5: closing the LAST session pops Terminal (pop-on-empty works)
  // ---------------------------------------------------------------------------
  testWidgets('closing last session pops Terminal screen', (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');
    final session = SshSession(host: host);

    final result = await _pump(tester, hosts: [host], sessions: [session]);

    // Navigate to Terminal.
    await tester.tap(find.byType(HostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MobileTerminalScreen), findsOneWidget);

    // Drain sessions — simulates the last session being closed.
    result.sp.setSessions([]);
    // Let didChangeDependencies fire and schedule the postFrameCallback.
    await tester.pump();
    // Let the postFrameCallback fire (pop-on-empty re-check runs here).
    await tester.pump();
    // Let Navigator complete the pop transition.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // Terminal screen should have been popped.
    expect(find.byType(MobileHostsScreen), findsOneWidget);
    expect(find.byType(MobileTerminalScreen), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // T6: no spurious pop when sessions go empty then non-empty in same frame
  // ---------------------------------------------------------------------------
  testWidgets(
      'no spurious pop when session added before postFrameCallback fires',
      (tester) async {
    final host = Host(label: 'prod', host: '10.0.0.1', username: 'root');
    final session = SshSession(host: host);
    final session2 = SshSession(host: host);

    final result = await _pump(tester, hosts: [host], sessions: [session]);

    // Navigate to Terminal.
    await tester.tap(find.byType(HostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MobileTerminalScreen), findsOneWidget);

    // Drain sessions → schedules the postFrameCallback (sets _popScheduled=true).
    result.sp.setSessions([]);
    await tester.pump(); // didChangeDependencies fires, callback queued

    // Before the callback fires, add a new session back.
    result.sp.setSessions([session2]);
    await tester.pump(); // postFrameCallback fires — re-checks, sees non-empty

    await tester.pump(const Duration(milliseconds: 300));

    // Terminal must still be visible — no spurious pop.
    expect(find.byType(MobileTerminalScreen), findsOneWidget);
  });
}
