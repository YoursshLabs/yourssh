import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/container_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/compose_panel.dart';

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

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  testWidgets('shows No Compose stacks found when discovery returns empty', (tester) async {
    final fake = _FakeSshService();
    // Both docker compose ls and find return empty
    fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('No Compose stacks found.'), findsOneWidget);
  });

  testWidgets('shows stack name when discovery returns a result', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (cmd) {
      if (cmd.contains('docker compose ls')) {
        return (
          stdout: '[{"Name":"myapp","Status":"running(2)","ConfigFiles":"/opt/myapp/compose.yml"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    expect(find.text('myapp'), findsOneWidget);
    expect(find.text('Up'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
  });

  testWidgets('shows service tile with Stop control after tapping a running stack', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (cmd) {
      if (cmd.contains('docker compose ls')) {
        return (
          stdout: '[{"Name":"myapp","Status":"running(1)","ConfigFiles":"/opt/myapp/compose.yml"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      if (cmd.contains('docker compose ps --format json')) {
        return (
          stdout: '[{"Name":"myapp-web-1","Service":"web","State":"running","Image":"nginx:latest"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    // Stack should be visible
    expect(find.text('myapp'), findsOneWidget);

    // Tap the stack tile to expand services
    await tester.tap(find.text('myapp'));
    await tester.pumpAndSettle();

    // Service row should render
    expect(find.text('web'), findsOneWidget);
    // Running service should show Stop control
    expect(find.byTooltip('Stop service'), findsOneWidget);
  });

  testWidgets('closes log panel when stack selection changes', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (cmd) {
      if (cmd.contains('docker compose ls')) {
        return (
          stdout:
              '[{"Name":"alpha","Status":"running(1)","ConfigFiles":"/opt/alpha/compose.yml"},'
              '{"Name":"beta","Status":"running(1)","ConfigFiles":"/opt/beta/compose.yml"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      if (cmd.contains('docker compose ps --format json')) {
        return (
          stdout: '[{"Name":"alpha-web-1","Service":"web","State":"running","Image":"nginx:latest"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    // Select the first stack to load its services
    await tester.tap(find.text('alpha'));
    await tester.pumpAndSettle();

    // Open the log panel for the service
    await tester.tap(find.byTooltip('Logs').first);
    await tester.pump();
    expect(find.textContaining('Logs:'), findsOneWidget);

    // Now select a different stack — log panel must close
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Logs:'), findsNothing);
  });

  testWidgets('shows + button for manual path input', (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (_) => (stdout: '', stderr: '', exitCode: 0);
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    await tester.tap(find.byTooltip('Add path manually'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('entering a non-absolute manual path shows error snackbar and does not add a stack', (tester) async {
    final fake = _FakeSshService();
    bool execCalled = false;
    fake.execStub = (cmd) {
      // validateComposeFile should NOT be called for a relative path.
      if (cmd.contains('config --services')) execCalled = true;
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    // Open manual input
    await tester.tap(find.byTooltip('Add path manually'));
    await tester.pump();

    // Enter a relative (non-absolute) path
    await tester.enterText(find.byType(TextField), 'relative/path/compose.yml');
    await tester.tap(find.text('Add'));
    await tester.pump();

    // An error snackbar should appear
    expect(find.byType(SnackBar), findsOneWidget);
    // validateComposeFile was never called (no SSH exec for config --services)
    expect(execCalled, isFalse);
    // No stack was added
    expect(find.text('relative'), findsNothing);
  });

  testWidgets('manually-added stack survives a refresh (not wiped by discovery)',
      (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (cmd) {
      // Discovery finds nothing (the path lives outside the scanned roots);
      // only validateComposeFile succeeds.
      if (cmd.contains('config --services')) {
        return (stdout: 'web\n', stderr: '', exitCode: 0);
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();

    // Add a manual path outside the discovery roots.
    await tester.tap(find.byTooltip('Add path manually'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), '/data/app/docker-compose.yml');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('app'), findsOneWidget);

    // Refresh — discovery still returns nothing; the manual stack must remain.
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('degraded service shows Stop control (treated as running)',
      (tester) async {
    final fake = _FakeSshService();
    fake.execStub = (cmd) {
      if (cmd.contains('docker compose ls')) {
        return (
          stdout:
              '[{"Name":"myapp","Status":"running(2)","ConfigFiles":"/opt/myapp/compose.yml"}]',
          stderr: '',
          exitCode: 0,
        );
      }
      if (cmd.contains('docker compose ps --format json')) {
        // 2-replica service, one running + one exited → 'degraded'.
        return (
          stdout:
              '{"Name":"myapp-web-1","Service":"web","State":"running","Image":"nginx"}\n'
              '{"Name":"myapp-web-2","Service":"web","State":"exited","Image":"nginx"}\n',
          stderr: '',
          exitCode: 0,
        );
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    final svc = ContainerService(fake);
    await tester.pumpWidget(_wrap(ComposePanel(host: host, service: svc)));
    await tester.pump();
    await tester.tap(find.text('myapp'));
    await tester.pumpAndSettle();

    expect(find.text('web'), findsOneWidget);
    expect(find.byTooltip('Stop service'), findsOneWidget);
    expect(find.byTooltip('Start service'), findsNothing);
  });
}
