import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/bulk_action_service.dart';
import 'package:yourssh/widgets/bulk/bulk_run_dialog.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show showYsDialog, YsDialogFrame;

import '../helpers/ys_test_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(Widget child) => ChangeNotifierProvider(
        create: (_) => SnippetProvider(),
        child: ysTestApp(child),
      );

  testWidgets('runs a command and shows per-host results', (tester) async {
    final hosts = [
      Host(label: 'a', host: 'a.x', username: 'u'),
      Host(label: 'b', host: 'b.x', username: 'u'),
    ];
    final service = BulkActionService(
        exec: (h, c) async => (stdout: 'up 1 day', stderr: '', exitCode: 0));

    await tester.pumpWidget(
        wrap(BulkRunDialog(hosts: hosts, serviceOverride: service)));
    expect(find.text('Run command on 2 hosts'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('bulk-command-field')), 'uptime');
    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.textContaining('2 ok'), findsOneWidget);
  });

  testWidgets('RUN does nothing with an empty command', (tester) async {
    var execCount = 0;
    final service = BulkActionService(exec: (h, c) async {
      execCount++;
      return (stdout: '', stderr: '', exitCode: 0);
    });
    await tester.pumpWidget(wrap(BulkRunDialog(
        hosts: [Host(label: 'a', host: 'a.x', username: 'u')],
        serviceOverride: service)));
    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();
    expect(execCount, 0);
  });

  testWidgets('Esc while running does not pop without confirm', (tester) async {
    final gate = Completer<({String stdout, String stderr, int exitCode})>();
    final service = BulkActionService(exec: (h, c) => gate.future);

    // Push the dialog as a real dialog route so PopScope operates on the route.
    late BuildContext dialogCtx;
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SnippetProvider(),
      child: MaterialApp(builder: ysRootBuilder,
        home: Builder(builder: (ctx) {
          dialogCtx = ctx;
          return const Scaffold(body: SizedBox());
        }),
      ),
    ));
    showYsDialog<void>(
dialogCtx, barrierDismissible: false, builder: (_) => BulkRunDialog(
        hosts: [Host(label: 'a', host: 'a.x', username: 'u')],
        serviceOverride: service,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('bulk-command-field')), 'sleep 100');
    await tester.tap(find.text('RUN'));
    // Pump once to start the run (futures fire, setState called).
    await tester.pump();
    // One more pump to let the state rebuild with isRunning=true.
    await tester.pump();

    // Confirm the CANCEL button is visible — proves isRunning is true.
    expect(find.text('CANCEL'), findsOneWidget);

    // Verify route-level pop disposition is doNotPop (PopScope registered).
    final dialogEl = tester.element(find.byType(BulkRunDialog));
    final route = ModalRoute.of(dialogEl);
    expect(route?.popDisposition, RoutePopDisposition.doNotPop,
        reason: 'PopScope canPop=false must set route disposition to doNotPop');

    // Simulate a system-back / Esc via maybePop. Note: maybePop returns true
    // for both pop and doNotPop cases; what matters is that the dialog is
    // still in the tree afterward.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await tester.pump();
    // Dialog widget must still be present — the pop was blocked.
    expect(find.byType(BulkRunDialog), findsOneWidget,
        reason: 'Dialog must remain after blocked pop');

    gate.complete((stdout: '', stderr: '', exitCode: 0));
    await tester.pumpAndSettle();
  });

  testWidgets('Enter in the command field starts the run', (tester) async {
    var execCount = 0;
    final service = BulkActionService(exec: (h, c) async {
      execCount++;
      return (stdout: 'ok', stderr: '', exitCode: 0);
    });
    await tester.pumpWidget(wrap(BulkRunDialog(
        hosts: [Host(label: 'a', host: 'a.x', username: 'u')],
        serviceOverride: service)));
    await tester.tap(find.byKey(const Key('bulk-command-field')));
    await tester.enterText(
        find.byKey(const Key('bulk-command-field')), 'uptime');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(execCount, 1);
    expect(find.textContaining('1 ok'), findsOneWidget);
  });

  testWidgets('does not overflow at 900x600 with long host labels',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = 'h' * 60;
    final service = BulkActionService(
        exec: (h, c) async => (stdout: 'x\n' * 5, stderr: '', exitCode: 0));
    await tester.pumpWidget(wrap(BulkRunDialog(hosts: [
      Host(label: long, host: 'a.x', username: 'u'),
      Host(label: '${long}b', host: 'b.x', username: 'u'),
    ], serviceOverride: service)));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(YsDialogFrame));
    expect(box.height, lessThanOrEqualTo(600),
        reason: 'dialog fits the 900x600 window');
    expect(box.width, lessThanOrEqualTo(900));
    expect(tester.takeException(), isNull);
    await tester.enterText(
        find.byKey(const Key('bulk-command-field')), 'uptime');
    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('DIFF'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
