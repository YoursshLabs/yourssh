import 'package:uuid/uuid.dart';

enum TransferDirection { upload, download }
enum TransferStatus { pending, inProgress, done, skipped, error }

class SftpTransferItem {
  final String id;
  final String fileName;
  final TransferDirection direction;
  TransferStatus status;
  int bytesTransferred;
  int totalBytes;
  String? errorMessage;

  SftpTransferItem({
    String? id,
    required this.fileName,
    required this.direction,
    this.status = TransferStatus.pending,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0;
}
