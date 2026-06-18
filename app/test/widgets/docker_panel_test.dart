import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/docker_panel.dart';

class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
      Host host, String cmd, {String? auditSource}) async =>
      execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) =>
      const Stream.empty();
}

// DockerPanel reaches into SessionProvider only inside the Exec button
// callback (context.read<SessionProvider>()); these tests never tap Exec, so
// no provider ancestor is needed — a bare MaterialApp suffices.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

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
  });
}
