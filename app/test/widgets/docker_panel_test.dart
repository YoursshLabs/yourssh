import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/docker_panel.dart';
import 'package:flutter/services.dart';

import '../helpers/tab_to.dart';
import '../helpers/ys_test_app.dart';

class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  final List<String> cmds = [];
  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;

  /// When set, exec awaits this gate before returning for `docker ps` calls
  /// — used to hold the post-action refresh in-flight and observe the UI.
  Completer<void>? psGate;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
      Host host, String cmd, {String? auditSource}) async {
    cmds.add(cmd);
    if (psGate != null && cmd.contains('docker ps')) await psGate!.future;
    return execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) =>
      const Stream.empty();
}

// DockerPanel reaches into SessionProvider only inside the Exec button
// callback (context.read<SessionProvider>()); these tests never tap Exec, so
// no provider ancestor is needed. forui widgets need the FTheme root.
Widget _wrap(Widget child) => ysTestApp(child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  testWidgets('shows running containers with Stop and Logs buttons', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('web'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Logs'), findsOneWidget);
    expect(find.byTooltip('Start'), findsNothing);
  });

  testWidgets('shows Start button for stopped container', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|worker|myimage:1.0|Exited (0) 5 minutes ago',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.byTooltip('Start'), findsOneWidget);
    expect(find.byTooltip('Stop'), findsNothing);
  });

  testWidgets('shows No containers found for empty list', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('No containers found.'), findsOneWidget);
  });

  testWidgets('tapping Logs opens log panel with container name header', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    await tester.tap(find.byTooltip('Logs'));
    await tester.pump();

    expect(find.text('Logs: web'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200)); // tappable timer
  });

  testWidgets('restarting container shows Stop/Restart, not Start', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Restarting (1) 2 seconds ago',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    expect(find.byTooltip('Stop'), findsOneWidget);
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(find.byTooltip('Start'), findsNothing);
  });

  testWidgets('tapping Stop runs docker stop and re-lists', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();

    await tester.tap(find.byTooltip('Stop'));
    await tester.pumpAndSettle();

    expect(fake.cmds.any((c) => c.contains('docker stop')), isTrue);
    // One ps at init + one after the action's refresh.
    expect(
        fake.cmds.where((c) => c.contains('docker ps')).length,
        greaterThanOrEqualTo(2));
  });

  testWidgets('post-action refresh keeps the list visible (no full-screen spinner)',
      (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(DockerPanel(host: host, service: svc)));
    await tester.pump();
    expect(find.text('web'), findsOneWidget);

    // Hold the post-action `docker ps` refresh in-flight.
    fake.psGate = Completer<void>();
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(); // action done; refresh now awaiting the gate

    // The list must remain — the action-scoped refresh must NOT replace the
    // whole panel with a full-screen spinner.
    expect(find.text('web'), findsOneWidget);

    fake.psGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('web'), findsOneWidget);
  });

  testWidgets('900x600 with a 60-char container name does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final name = 'c' * 60;
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|$name|${'i' * 60}:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    await tester.pumpWidget(
        _wrap(DockerPanel(host: host, service: ContainerService(fake))));
    await tester.pump();
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('Logs: $name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard: Enter on a focused Stop button runs docker stop',
      (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    await tester.pumpWidget(
        _wrap(DockerPanel(host: host, service: ContainerService(fake))));
    await tester.pump();

    Focus.of(tester.element(find.descendant(of: find.byTooltip('Stop'), matching: find.byType(Icon)))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds.any((c) => c.contains('docker stop')), isTrue);
  });

  testWidgets('log panel Clear and Close buttons work', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    await tester.pumpWidget(
        _wrap(DockerPanel(host: host, service: ContainerService(fake))));
    await tester.pump();
    await tester.tap(find.byTooltip('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);
    expect(find.byTooltip('Close logs'), findsOneWidget);
    await tester.tap(find.byTooltip('Close logs'));
    await tester.pumpAndSettle();
    expect(find.text('Logs: web'), findsNothing);
  });

  testWidgets('keyboard: Tab from the first control reaches Stop, Enter runs it',
      (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (
      stdout: 'abc123|web|nginx:latest|Up 2 hours',
      stderr: '',
      exitCode: 0,
    );
    await tester.pumpWidget(
        _wrap(DockerPanel(host: host, service: ContainerService(fake))));
    await tester.pump();
    final presses = await tabTo(tester, find.byTooltip('Stop'));
    expect(presses, 2); // Refresh, then Stop
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fake.cmds.any((c) => c.contains('docker stop')), isTrue);
  });
}
