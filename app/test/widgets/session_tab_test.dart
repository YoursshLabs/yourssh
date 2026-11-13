import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
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
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

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
      child: ysTestApp(Row(children: [tab])),
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

  testWidgets('keyboard: Tab focuses the tab, Enter selects it, Tab again '
      'reaches the hidden close button and Enter closes', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host);
    var selected = 0;

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: false,
            provider: sessions,
            onTap: () => selected++),
        sessions,
        hosts));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, 1);
    expect(sessions.sessions, hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sessions.sessions, isEmpty);
  });

  testWidgets('keyboard: a pinned tab is selectable but has no close button',
      (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host, pinned: true);
    var selected = 0;

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: false,
            provider: sessions,
            onTap: () => selected++),
        sessions,
        hosts));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(selected, 1);
    expect(find.byType(FButton), findsNothing);
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

  testWidgets('key icon shows success color when active', (tester) async {
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

    expect(tester.widget<Icon>(find.byIcon(Icons.key)).color, AppColors.success);
  });

  testWidgets('key icon colors for ready and fallback states', (tester) async {
    final fwdHost = Host(
        id: 'h11',
        label: 'fwd3',
        host: '9.9.9.11',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, fwdHost); // starts ready

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));
    expect(tester.widget<Icon>(find.byIcon(Icons.key)).color,
        AppColors.textSecondary);

    session.agentForwardingState = AgentForwardingState.fallback;
    await tester.pumpWidget(wrap(
        SessionTab(
            session: session, isActive: true, provider: sessions, onTap: () {}),
        sessions,
        hosts));
    expect(
        tester.widget<Icon>(find.byIcon(Icons.key)).color, AppColors.orange);
  });

  group('context menu', () {
    Future<(SessionProvider, SshSession)> openMenu(WidgetTester tester,
        {bool pinned = false}) async {
      final (sessions, hosts) = makeProviders();
      final session = seedSession(sessions, host, pinned: pinned);
      await tester.pumpWidget(wrap(
          SessionTab(
              session: session,
              isActive: true,
              provider: sessions,
              onTap: () {}),
          sessions,
          hosts));
      final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
      await gesture.down(tester.getCenter(find.byType(SessionTab)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return (sessions, session);
    }

    Color? textColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style?.color;

    testWidgets('uses card surface, token text and Lucide icons',
        (tester) async {
      await openMenu(tester);
      for (final t in ['Rename', 'Pin', 'Color tag', 'Close']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(textColor(tester, 'Rename'), YsColors.foreground);
      expect(textColor(tester, 'Pin'), YsColors.foreground);
      expect(textColor(tester, 'Color tag'), YsColors.foreground);
      expect(textColor(tester, 'Close'), YsColors.mutedForeground);
      expect(find.byIcon(FLucideIcons.pencil), findsOneWidget);
      expect(find.byIcon(FLucideIcons.pin), findsWidgets);
      expect(find.byIcon(FLucideIcons.palette), findsOneWidget);
      expect(find.byIcon(FLucideIcons.x), findsWidgets);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('menu surface is the card token', (tester) async {
      await openMenu(tester);
      final route = ModalRoute.of(tester.element(find.text('Rename')))!;
      expect(route, isA<PopupRoute<String>>());
      final popup = tester.widget<Material>(find
          .ancestor(of: find.text('Rename'), matching: find.byType(Material))
          .last);
      expect(popup.color, YsColors.card);
    });

    testWidgets('Pin toggles, Close closes', (tester) async {
      final (sessions, session) = await openMenu(tester);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();
      expect(session.isPinned, isTrue);
      expect(sessions.sessions, hasLength(1));
    });

    testWidgets('color submenu lists None and colours with token text',
        (tester) async {
      final (sessions, session) = await openMenu(tester);
      await tester.tap(find.text('Color tag'));
      await tester.pumpAndSettle();
      expect(textColor(tester, 'None'), YsColors.mutedForeground);
      expect(textColor(tester, 'Red'), YsColors.foreground);
      await tester.tap(find.text('Red'));
      await tester.pumpAndSettle();
      expect(session.colorTag, '#ef4444');
      expect(sessions.sessions, hasLength(1));
    });
  });
}
