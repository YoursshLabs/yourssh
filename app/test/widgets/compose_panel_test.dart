import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/container_entry.dart';
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
}
