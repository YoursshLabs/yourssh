// Regression: the overlay rendered the previous SSH host's rx/tx numbers
// over local terminal tabs because nothing cleared the last delta (or even
// re-evaluated the active session) on tab switch.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/network_stats.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/pty_runner.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/network_stats_overlay.dart';

class _FakePty implements PtyRunner {
  final _output = StreamController<List<int>>();
  final _exit = Completer<int>();

  @override
  Stream<List<int>> get output => _output.stream;
  @override
  void write(Uint8List data) {}
  @override
  void resize(int rows, int cols) {}
  @override
  void kill() {}
  @override
  Future<int> get exitCode => _exit.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  testWidgets('switching to a local tab hides the previous host stats',
      (tester) async {
    SharedPreferences.setMockInitialValues({'networkStatsEnabled': true});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null));

    final settings = SettingsProvider();
    final sshService = SshService(StorageService());
    final sessions = SessionProvider(sshService, TabMetadataService());
    addTearDown(sessions.dispose);
    sessions.localShell =
        LocalShellService(ptyFactory: (s, c, r, env) => _FakePty());

    final ssh = SshSession(
      host: Host(
        id: 'h1',
        label: 'h1',
        host: 'h1.example.com',
        port: 22,
        username: 'user',
      ),
    );
    sessions.addWatchSession(ssh);
    await sessions.newLocalSession();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sessions),
          Provider<SshService>.value(value: sshService),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NetworkStatsOverlay()),
        ),
      ),
    );
    await tester.pump(); // settings async load

    // Focus the SSH tab and inject a polled delta.
    sessions.setActive(ssh.id);
    await tester.pump();
    final dynamic state = tester.state(find.byType(NetworkStatsOverlay));
    state.debugSetDelta(
        const NetworkStatsDelta(rxBytesPerSec: 1024, txBytesPerSec: 2048));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget,
        reason: 'precondition: stats render on the SSH tab');

    // Switch to the local terminal tab.
    sessions.setActive((sessions.sessions
            .firstWhere((s) => s.id != ssh.id))
        .id);
    await tester.pump();

    expect(find.byIcon(Icons.arrow_downward), findsNothing,
        reason: 'stale SSH stats must not render over a local tab');
  });
}
