import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/health_monitor_service.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/session_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  (SessionProvider, HostProvider) makeProviders() {
    final storage = StorageService();
    final sessions = SessionProvider(SshService(storage), TabMetadataService());
    final hosts = HostProvider(storage);
    return (sessions, hosts);
  }

  Widget wrap(Widget tab, SessionProvider sessions, HostProvider hosts) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: hosts),
        ChangeNotifierProvider(create: (_) => ShellIntegrationProvider()),
        ChangeNotifierProvider(
            create: (_) =>
                RecordingProvider(RecordingService(), getPath: () => '/tmp')),
        ChangeNotifierProvider(
            create: (_) => HealthMonitorService(
                measure: (_) async => null,
                connectedHostIds: () => const <String>[],
                pollSeconds: () => 0)),
      ],
      child: MaterialApp(home: Scaffold(body: Row(children: [tab]))),
    );
  }

  SshSession seedSession(SessionProvider sessions, Host host,
      {bool pinned = false}) {
    final session = SshSession(
        host: host, status: SessionStatus.connected, isPinned: pinned);
    sessions.sessions.add(session);
    return session;
  }

  Future<void> middleClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kTertiaryButton);
    await gesture.down(tester.getCenter(finder));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  final host =
      Host(id: 'h1', label: 'prod', host: '1.2.3.4', port: 22, username: 'u');

  testWidgets('middle-click closes an unpinned tab', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    await middleClick(tester, find.byType(SessionTab));
    expect(sessions.sessions, isEmpty);
  });

  testWidgets('middle-click is ignored on a pinned tab', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host, pinned: true);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    await middleClick(tester, find.byType(SessionTab));
    expect(sessions.sessions, hasLength(1));
  });

  testWidgets('shows distro icon when the host has a detectedOs',
      (tester) async {
    final (sessions, hosts) = makeProviders();
    final ubuntuHost = Host(
        id: 'h2',
        label: 'web',
        host: '5.6.7.8',
        port: 22,
        username: 'u',
        detectedOs: 'ubuntu');
    await hosts.addHost(ubuntuHost);
    final session = seedSession(sessions, ubuntuHost);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    expect(
        find.byWidgetPredicate((w) =>
            w is SvgPicture &&
            (w.bytesLoader as SvgAssetLoader).assetName ==
                'assets/os/ubuntu.svg'),
        findsOneWidget);
  });

  testWidgets('no OS icon when detectedOs is unknown', (tester) async {
    final (sessions, hosts) = makeProviders();
    await hosts.addHost(host); // detectedOs == null
    final session = seedSession(sessions, host);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('no key icon when the host has forwarding off', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host); // forwarding off by default

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));

    expect(find.byIcon(Icons.key), findsNothing);
  });

  testWidgets('key icon color and tooltip track the forwarding state',
      (tester) async {
    final fwdHost = Host(
        id: 'h9',
        label: 'fwd',
        host: '9.9.9.9',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, fwdHost);
    session.agentForwardingState = AgentForwardingState.refused;

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));

    final icon = tester.widget<Icon>(find.byIcon(Icons.key));
    expect(icon.color, AppColors.red);
    expect(
      find.byTooltip(
          'Agent forwarding refused by server (AllowAgentForwarding no)'),
      findsOneWidget,
    );
  });

  testWidgets('key icon shows accent color when active', (tester) async {
    final fwdHost = Host(
        id: 'h10',
        label: 'fwd2',
        host: '9.9.9.10',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, fwdHost);
    session.agentForwardingState = AgentForwardingState.active;

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));

    expect(tester.widget<Icon>(find.byIcon(Icons.key)).color, AppColors.accent);
  });
}
