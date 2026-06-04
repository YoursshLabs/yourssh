import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/sftp_transfer_provider.dart';
import 'package:yourssh/models/sftp_transfer_item.dart';

void main() {
  group('SftpTransferProvider', () {
    test('isTransferring is false when empty', () {
      expect(SftpTransferProvider().isTransferring, false);
    });

    test('isTransferring is true when an item is inProgress', () {
      final p = SftpTransferProvider();
      final item = SftpTransferItem(fileName: 'a.txt', direction: TransferDirection.upload)
        ..status = TransferStatus.inProgress;
      p.startBatch([item]);
      expect(p.isTransferring, true);
    });

    test('overallProgress is 0 with no items', () {
      expect(SftpTransferProvider().overallProgress, 0.0);
    });

    test('overallProgress calculates from total bytes', () {
      final p = SftpTransferProvider();
      final item = SftpTransferItem(fileName: 'a.txt', direction: TransferDirection.upload)
        ..totalBytes = 1000
        ..bytesTransferred = 250;
      p.startBatch([item]);
      expect(p.overallProgress, 0.25);
    });

    test('updateItem modifies the matching item', () {
      final p = SftpTransferProvider();
      final item = SftpTransferItem(id: 'abc', fileName: 'a.txt', direction: TransferDirection.upload)
        ..totalBytes = 1000;
      p.startBatch([item]);
      p.updateItem('abc', bytesTransferred: 500, status: TransferStatus.inProgress);
      expect(p.items.first.bytesTransferred, 500);
      expect(p.items.first.status, TransferStatus.inProgress);
    });

    test('cancel sets isCancelled to true', () {
      final p = SftpTransferProvider();
      p.cancel();
      expect(p.isCancelled, true);
    });

    test('clear removes all items and resets cancelled', () {
      final p = SftpTransferProvider();
      p.startBatch([SftpTransferItem(fileName: 'a.txt', direction: TransferDirection.upload)]);
      p.cancel();
      p.clear();
      expect(p.items, isEmpty);
      expect(p.isCancelled, false);
    });

    test('startBatch appends while a batch is still transferring', () {
      final p = SftpTransferProvider();
      p.startBatch([
        SftpTransferItem(id: '1', fileName: 'a.txt', direction: TransferDirection.upload)
          ..status = TransferStatus.inProgress,
      ]);
      p.startBatch([
        SftpTransferItem(id: '2', fileName: 'b.txt', direction: TransferDirection.upload),
      ]);
      expect(p.items.map((i) => i.id), ['1', '2'],
          reason: 'a running batch must not be clobbered by a new one');
    });

    test('startBatch replaces the list when the previous batch finished', () {
      final p = SftpTransferProvider();
      p.startBatch([
        SftpTransferItem(id: '1', fileName: 'a.txt', direction: TransferDirection.upload)
          ..status = TransferStatus.done,
      ]);
      p.startBatch([
        SftpTransferItem(id: '2', fileName: 'b.txt', direction: TransferDirection.upload),
      ]);
      expect(p.items.map((i) => i.id), ['2']);
    });

    test('cancel marks unfinished items skipped so isTransferring releases',
        () {
      final p = SftpTransferProvider();
      p.startBatch([
        SftpTransferItem(id: '1', fileName: 'a.txt', direction: TransferDirection.upload)
          ..status = TransferStatus.done,
        SftpTransferItem(id: '2', fileName: 'b.txt', direction: TransferDirection.upload)
          ..status = TransferStatus.inProgress,
        SftpTransferItem(id: '3', fileName: 'c.txt', direction: TransferDirection.upload),
      ]);
      p.cancel();
      expect(p.items[0].status, TransferStatus.done);
      expect(p.items[1].status, TransferStatus.skipped);
      expect(p.items[2].status, TransferStatus.skipped);
      expect(p.isTransferring, isFalse,
          reason: 'a cancelled batch must not latch isTransferring');
    });

    test('completedCount counts done and skipped items', () {
      final p = SftpTransferProvider();
      p.startBatch([
        SftpTransferItem(id: '1', fileName: 'a.txt', direction: TransferDirection.upload)..status = TransferStatus.done,
        SftpTransferItem(id: '2', fileName: 'b.txt', direction: TransferDirection.upload)..status = TransferStatus.skipped,
        SftpTransferItem(id: '3', fileName: 'c.txt', direction: TransferDirection.upload),
      ]);
      expect(p.completedCount, 2);
    });
  });
}
