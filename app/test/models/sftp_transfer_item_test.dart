// app/test/models/sftp_transfer_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/sftp_transfer_item.dart';

void main() {
  group('SftpTransferItem', () {
    test('progress is 0 when totalBytes is 0', () {
      final item = SftpTransferItem(
        id: '1',
        fileName: 'file.txt',
        direction: TransferDirection.upload,
      );
      expect(item.progress, 0.0);
    });

    test('progress calculates correctly', () {
      final item = SftpTransferItem(
        id: '2',
        fileName: 'file.txt',
        direction: TransferDirection.download,
      )
        ..totalBytes = 1000
        ..bytesTransferred = 500;
      expect(item.progress, 0.5);
    });

    test('initial status is pending', () {
      final item = SftpTransferItem(
        id: '3',
        fileName: 'file.txt',
        direction: TransferDirection.upload,
      );
      expect(item.status, TransferStatus.pending);
    });
  });
}
