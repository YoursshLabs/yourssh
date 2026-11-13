import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/containers_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/tab_to.dart';
import '../helpers/ys_test_app.dart';

class _FakeSsh extends SshService {
  _FakeSsh() : super(StorageService());

  final List<String> cmds = [];
  bool dockerOk = true;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String cmd, {
    String? auditSource,
  }) async {
    cmds.add(cmd);
    if (cmd == 'command -v docker' && !dockerOk) {
      return (stdout: '', stderr: '', exitCode: 1);
    }
    if (cmd.startsWith('docker ps')) {
      return (
        stdout: 'abc|web|nginx:latest|Up 2 hours',
        stderr: '',
        exitCode: 0,
      );
    }
    return (stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeSsh> pump(WidgetTester tester,
      {String username = 'u', bool withSession = true, bool dockerOk = true}) async {
    final fake = _FakeSsh()..dockerOk = dockerOk;
    final sessions = SessionProvider(fake, TabMetadataService());
    if (withSession) {
      sessions.sessions.add(SshSession(
        host: Host(label: 'h', host: 'srv', port: 22, username: username),
        status: SessionStatus.connected,
      ));
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<SshService>.value(value: fake),
        ChangeNotifierProvider.value(value: sessions),
      ],
      child: ysTestApp(const ContainersScreen()),
    ));
    await tester.pump();
    return fake;
  }

  testWidgets('without a session shows the open-a-session hint', (tester) async {
    await pump(tester, withSession: false);
    expect(
      find.text('Open an SSH session first, then come back to browse containers.'),
      findsOneWidget,
    );
  });

  testWidgets('smoke: tabs, rescan, scan then docker panel', (tester) async {
    final fake = await pump(tester);
    expect(find.byType(FTabs), findsOneWidget);
    expect(find.text('Docker'), findsOneWidget);
    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Kubernetes'), findsOneWidget);
    expect(find.byTooltip('Rescan runtimes'), findsOneWidget);
    expect(find.byKey(const ValueKey('containers-session')), findsOneWidget);
    expect(find.text('Tap refresh to scan for Docker / Kubernetes.'),
        findsOneWidget);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('web'), findsOneWidget);
    expect(fake.cmds, contains('command -v docker'));

    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    expect(find.text('Compose Stacks'), findsOneWidget);
  });

  testWidgets('not installed shows install hint with Copy command',
      (tester) async {
    await pump(tester, dockerOk: false);
    await tester.tap(find.byTooltip('Rescan runtimes'));
    await tester.pumpAndSettle();
    expect(find.text('docker is not installed on this host'), findsOneWidget);
    expect(find.text('Copy command'), findsOneWidget);
  });

  testWidgets('keyboard: Enter on the focused Scan button scans', (tester) async {
    final fake = await pump(tester);
    Focus.of(tester.element(find.text('Scan'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds, contains('command -v docker'));
    expect(find.text('web'), findsOneWidget);
  });

  testWidgets('900x600 with a 60-char session title does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, username: 'u' * 60);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard: Tab from the first control reaches Scan, Enter scans',
      (tester) async {
    final fake = await pump(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final presses = await tabTo(tester, find.text('Scan'));
    expect(presses, 6); // measured: select, rescan, tab stops, Scan
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds, contains('command -v docker'));
  });
}
