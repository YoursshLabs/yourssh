import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/navigation/open_session.dart';
import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/theme/app_theme.dart';

Future<SessionProvider> _pump(WidgetTester t, Host host,
    {void Function(SessionProvider)? seed}) async {
  final sessions =
      SessionProvider(SshService(StorageService()), TabMetadataService());
  seed?.call(sessions);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ChangeNotifierProvider<HostProvider>(
          create: (_) => HostProvider(StorageService())),
      ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider()),
    ],
    child: MaterialApp(
      builder: ysRootBuilderTouch,
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => openMobileSession(Navigator.of(ctx), host),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  return sessions;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an RDP host is refused on mobile: notice, no session, no route',
      (t) async {
    final host = Host(
        label: 'Win', host: '1.1.1.1', username: 'a', protocol: HostProtocol.rdp);
    final sessions = await _pump(t, host);
    expect(sessions.sessions, isEmpty);
    expect(find.text('RDP and VNC hosts open in the desktop app'),
        findsOneWidget);
    expect(find.byType(MobileTerminalScreen), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('an SSH host with a live session reuses it', (t) async {
    final host = Host(label: 'Box', host: '127.0.0.1', username: 'a');
    late int before;
    final sessions = await _pump(t, host, seed: (sp) {
      sp.sessions.add(SshSession(host: host));
      before = sp.sessions.length;
    });
    expect(sessions.sessions.length, before);
    expect(find.byType(MobileTerminalScreen), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
