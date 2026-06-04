// Docked, minimizable transfer panel (replaces the modal SftpTransferDialog):
// transfers run in the provider regardless of panel state, the panel is just
// a non-blocking bottom view.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/sftp_transfer_item.dart';
import 'package:yourssh/providers/sftp_transfer_provider.dart';
import 'package:yourssh/widgets/sftp_transfer_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SftpTransferProvider tp;

  setUp(() => tp = SftpTransferProvider());
  tearDown(() => tp.dispose());

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tp,
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [SftpTransferPanel()])),
        ),
      ),
    );
    await tester.pump();
  }

  SftpTransferItem item(String id, String name,
          {TransferStatus status = TransferStatus.pending}) =>
      SftpTransferItem(
          id: id, fileName: name, direction: TransferDirection.upload)
        ..status = status;

  testWidgets('hidden when there are no items', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('expanded by default: header, progress and file rows',
      (tester) async {
    tp.startBatch([
      item('1', 'a.txt', status: TransferStatus.done),
      item('2', 'b.zip', status: TransferStatus.inProgress),
    ]);
    await pumpPanel(tester);

    expect(find.textContaining('1 / 2'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.text('b.zip'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('minimize collapses to a strip and expand restores',
      (tester) async {
    tp.startBatch([
      item('1', 'a.txt', status: TransferStatus.inProgress),
    ]);
    await pumpPanel(tester);

    await tester.tap(find.byTooltip('Minimize'));
    await tester.pump();
    expect(find.text('a.txt'), findsNothing,
        reason: 'file rows hidden in the strip');
    expect(find.textContaining('0 / 1'), findsOneWidget,
        reason: 'count stays visible in the strip');

    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('a.txt'), findsOneWidget);
  });

  testWidgets('auto-clears ~3s after a fully successful batch',
      (tester) async {
    tp.startBatch([item('1', 'a.txt', status: TransferStatus.inProgress)]);
    await pumpPanel(tester);

    tp.updateItem('1', status: TransferStatus.done);
    await tester.pump();
    expect(find.text('a.txt'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(tp.items, isEmpty,
        reason: 'successful batch should auto-dismiss');
  });

  testWidgets('stays visible when a file errored, close button clears',
      (tester) async {
    tp.startBatch([
      item('1', 'a.txt', status: TransferStatus.done),
      item('2', 'b.zip', status: TransferStatus.error),
    ]);
    await pumpPanel(tester);

    await tester.pump(const Duration(seconds: 4));
    expect(tp.items, isNotEmpty,
        reason: 'errors must stay visible until dismissed');
    expect(find.text('b.zip'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(tp.items, isEmpty);
  });

  testWidgets('Cancel wires to provider.cancel', (tester) async {
    tp.startBatch([item('1', 'a.txt', status: TransferStatus.inProgress)]);
    await pumpPanel(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tp.isCancelled, isTrue);
    // Cancel marks leftovers skipped → batch is finished (not successful?
    // skipped counts as completed) — panel may auto-clear afterwards.
    await tester.pump(const Duration(seconds: 4));
  });
}
