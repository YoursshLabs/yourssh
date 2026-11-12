import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/kubernetes_panel.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakeSsh extends SshService {
  _FakeSsh() : super(StorageService());

  final List<String> cmds = [];
  final List<String> streams = [];
  ({String stdout, String stderr, int exitCode}) Function(String cmd)? stub;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String cmd, {
    String? auditSource,
  }) async {
    cmds.add(cmd);
    return stub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) {
    streams.add(cmd);
    // Stays open: a closed stream makes the panel dismiss itself.
    final c = StreamController<String>();
    c.add('line one');
    addTearDown(c.close);
    return c.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  Widget wrap(_FakeSsh fake, {void Function(String)? onOpenBrowser}) =>
      Provider<SshService>.value(
        value: fake,
        child: ysTestApp(
          KubernetesPanel(host: host, onOpenBrowser: onOpenBrowser),
        ),
      );

  _FakeSsh podsFake(String podName, {String containers = 'app'}) {
    final fake = _FakeSsh();
    fake.stub = (cmd) {
      if (cmd.startsWith('kubectl get pods')) {
        return (
          stdout:
              'NAME READY STATUS RESTARTS AGE\n$podName 1/1 Running 0 5m\n',
          stderr: '',
          exitCode: 0,
        );
      }
      if (cmd.contains('jsonpath')) {
        return (stdout: containers, stderr: '', exitCode: 0);
      }
      if (cmd.contains('get-contexts')) {
        return (stdout: 'ctx-a\nctx-b\n', stderr: '', exitCode: 0);
      }
      return (stdout: '', stderr: '', exitCode: 0);
    };
    return fake;
  }

  testWidgets('smoke: header controls and scan, then pod actions', (tester) async {
    final fake = podsFake('web-1');
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.text('All namespaces'), findsOneWidget);
    expect(find.byType(FCheckbox), findsOneWidget);
    expect(find.byKey(const ValueKey('k8s-namespace')), findsOneWidget);
    expect(find.byKey(const ValueKey('k8s-context')), findsOneWidget);
    expect(find.text('No pods. Tap refresh to scan.'), findsOneWidget);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('web-1'), findsOneWidget);
    expect(find.byTooltip('Exec'), findsOneWidget);
    expect(find.byTooltip('Logs'), findsOneWidget);
    expect(find.byTooltip('Forward port'), findsOneWidget);
    expect(fake.cmds.any((c) => c.startsWith("kubectl get pods -n 'default'")),
        isTrue);
  });

  testWidgets('900x600 with a 60-char pod name does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final name = 'p' * 60;
    final fake = podsFake(name);
    await tester.pumpWidget(wrap(fake));
    await tester.pump();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Open the log panel too: it must fit under the list.
    await tester.tap(find.byTooltip('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('line one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard: Enter on a focused Logs button opens the log panel',
      (tester) async {
    final fake = podsFake('web-1');
    await tester.pumpWidget(wrap(fake));
    await tester.pump();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    Focus.of(tester.element(find.descendant(of: find.byTooltip('Logs'), matching: find.byType(Icon)))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('pod/web-1  •  app'), findsOneWidget);
    expect(find.byTooltip('Close logs'), findsOneWidget);
    expect(fake.streams.single, contains('kubectl logs -f'));
    await tester.tap(find.byTooltip('Close logs'));
    await tester.pumpAndSettle();
    expect(find.text('pod/web-1  •  app'), findsNothing);
  });

  testWidgets('multi-container pod asks which container before logs',
      (tester) async {
    final fake = podsFake('web-1', containers: 'app sidecar');
    await tester.pumpWidget(wrap(fake));
    await tester.pump();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('Select container'), findsOneWidget);
    await tester.tap(find.text('sidecar'));
    await tester.pumpAndSettle();
    expect(fake.streams.single, contains("-c 'sidecar'"));
  });

  testWidgets('forward port dialog validates then lists the active forward bar',
      (tester) async {
    final fake = podsFake('web-1');
    await tester.pumpWidget(wrap(fake));
    await tester.pump();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Forward port'));
    await tester.pumpAndSettle();
    expect(find.text('Forward port'), findsWidgets);
    await tester.tap(find.text('Start Forward'));
    await tester.pumpAndSettle();
    expect(find.text('1–65535'), findsWidgets); // still open, errors shown
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Start Forward'), findsNothing);
  });
}
