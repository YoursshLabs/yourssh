import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/bulk_action_service.dart';
import 'package:yourssh/widgets/bulk/bulk_push_dialog.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show showYsDialog, YsDialogFrame;

import '../helpers/ys_test_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(Widget child) => ChangeNotifierProvider(
      create: (_) => SnippetProvider(), child: ysTestApp(child));

  final service = BulkActionService(
      uploadFile: (h, l, r, {onProgress}) async {},
      mkdir: (h, p) async {});

  testWidgets('smoke: title, actions, default destination, overwrite warning',
      (tester) async {
    await tester.pumpWidget(wrap(BulkPushDialog(
        hosts: [
          Host(label: 'a', host: 'a.x', username: 'u'),
          Host(label: 'b', host: 'b.x', username: 'u'),
        ],
        serviceOverride: service)));
    expect(find.text('Push files to 2 hosts'), findsOneWidget);
    expect(find.text('Add files'), findsOneWidget);
    expect(find.text('Add folder'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Existing remote files will be overwritten.'),
        findsOneWidget);
    expect(find.text('Nothing run yet.'), findsOneWidget);
    final dest = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const Key('bulk-dest-field')),
        matching: find.byType(EditableText)));
    expect(dest.controller.text, '/tmp');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a relative destination shows the validation error',
      (tester) async {
    await tester.pumpWidget(wrap(BulkPushDialog(
        hosts: [Host(label: 'a', host: 'a.x', username: 'u')],
        serviceOverride: service)));
    await tester.enterText(find.byKey(const Key('bulk-dest-field')), 'tmp');
    await tester.pumpAndSettle();
    expect(find.text('Must be an absolute path'), findsOneWidget);
  });

  testWidgets('CLOSE pops an idle dialog', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SnippetProvider(),
        child: ysTestApp(Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }))));
    showYsDialog<void>(ctx,
        barrierDismissible: false,
        builder: (_) => BulkPushDialog(
            hosts: [Host(label: 'a', host: 'a.x', username: 'u')],
            serviceOverride: service));
    await tester.pumpAndSettle();
    expect(find.byType(BulkPushDialog), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(BulkPushDialog), findsNothing);
  });

  testWidgets('does not overflow at 900x600 with long host labels',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(BulkPushDialog(
        hosts: [Host(label: 'h' * 60, host: 'a.x', username: 'u')],
        serviceOverride: service)));
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(YsDialogFrame));
    expect(box.height, lessThanOrEqualTo(600),
        reason: 'dialog fits the 900x600 window');
    expect(box.width, lessThanOrEqualTo(900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at 900x600 with a long source and a running push',
      (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gate = Completer<void>();
    final slow = BulkActionService(
        uploadFile: (h, l, r, {onProgress}) async {
          onProgress?.call(10, 100);
          await gate.future;
        },
        uploadDirectory: ({
          required host,
          required localDir,
          required remoteDir,
          required onProgress,
          required isCancelled,
        }) async {},
        mkdir: (h, p) async {});
    final longName = '${'s' * 56}.txt'; // 60 chars
    await tester.pumpWidget(wrap(BulkPushDialog(
        hosts: [
          Host(label: 'h' * 60, host: 'a.x', username: 'u'),
          Host(label: '${'i' * 59}j', host: 'b.x', username: 'u'),
        ],
        initialSources: [
          BulkPushSource(path: '/tmp/$longName', isDirectory: false, bytes: 100),
        ],
        serviceOverride: slow)));
    await tester.pumpAndSettle();
    expect(find.textContaining('sssss'), findsWidgets,
        reason: 'the long source chip is shown');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cancel'), findsOneWidget, reason: 'push is running');
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byType(YsDialogFrame));
    expect(box.height, lessThanOrEqualTo(600));
    expect(box.width, lessThanOrEqualTo(900));

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
