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
  final List<SshSession> _injected;
  int connectAnyCalls = 0;

  _FakeSessionProvider(this._injected)
      : super(SshService(StorageService()), TabMetadataService());

  @override
  List<SshSession> get sshSessions => List.unmodifiable(_injected);

  /// Override the real connectAny so no SSH dial happens.
  @override
  Future<AppSession?> connectAny(Host host, {String? initialCommand}) async {
    connectAnyCalls++;
    // The session is already injected; return null like the SSH path does.
    return null;
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
}) async {
  SharedPreferences.setMockInitialValues({});
  final hp = HostProvider(StorageService());
  for (final h in hosts) {
    await hp.addHost(h);
  }

  final sp = _FakeSessionProvider(sessions);
  final probe = HostReachabilityProbe(connector: (_, __, ___) async {});
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
}
