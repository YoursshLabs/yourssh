import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

import '../helpers/ys_test_app.dart';

class _Sessions extends SessionProvider {
  _Sessions(this.list)
      : super(SshService(StorageService()), TabMetadataService());
  final List<SshSession> list;
  @override
  List<SshSession> get sshSessions => list;
}

void main() {
  testWidgets('terminal shows the paused state and mounts no TerminalView',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = SshSession(
      host: Host(id: 'h', label: 'h', host: 'h.com', username: 'u'),
      status: SessionStatus.disconnected,
    )..paused = true;
    final sessions = _Sessions([s]);
    final settings = SettingsProvider();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: ysTestApp(const MobileTerminalScreen(), touch: true),
    ));
    await t.pump();
    expect(find.text('Session paused — reconnecting'), findsOneWidget);
    expect(find.byType(TerminalView), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
