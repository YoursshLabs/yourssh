import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/app_session.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

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
      theme: buildMobileTheme(),
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
}
