import 'package:flutter/foundation.dart';
import '../models/sftp_transfer_item.dart';

class SftpTransferProvider extends ChangeNotifier {
  List<SftpTransferItem> _items = [];
  bool _cancelled = false;

  List<SftpTransferItem> get items => List.unmodifiable(_items);
  bool get isCancelled => _cancelled;

  bool get isTransferring =>
      _items.any((i) => i.status == TransferStatus.inProgress);

  double get overallProgress {
    final total = _items.fold<int>(0, (s, i) => s + i.totalBytes);
    if (total == 0) return 0;
    return _items.fold<int>(0, (s, i) => s + i.bytesTransferred) / total;
  }

  int get completedCount => _items
      .where((i) => i.status == TransferStatus.done || i.status == TransferStatus.skipped)
      .length;

  int get totalCount => _items.length;

  void startBatch(List<SftpTransferItem> items) {
    _items = List.of(items);
    _cancelled = false;
    notifyListeners();
  }

  // Per-byte progress updates rebuild every transfer-list widget; throttle to
  // ~30fps for byte-only updates. Status/error transitions always notify so
  // completion / failure shows up immediately.
  static const _progressNotifyInterval = Duration(milliseconds: 33);
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);

  void updateItem(String id, {int? bytesTransferred, TransferStatus? status, String? errorMessage}) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    final item = _items[idx];
    if (bytesTransferred != null) item.bytesTransferred = bytesTransferred;
    if (status != null) item.status = status;
    if (errorMessage != null) item.errorMessage = errorMessage;

    final isStatusChange = status != null || errorMessage != null;
    if (isStatusChange) {
      _lastProgressNotify = DateTime.now();
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastProgressNotify) >= _progressNotifyInterval) {
      _lastProgressNotify = now;
      notifyListeners();
    }
  }

  void cancel() {
    _cancelled = true;
    notifyListeners();
  }

  void clear() {
    _items = [];
    _cancelled = false;
    notifyListeners();
  }
}
