import 'package:flutter/foundation.dart';

import '../models/audit_event.dart';
import '../services/audit_service.dart';

/// Filter state + lazy paging for the audit viewer. Pages are 200 rows;
/// [hasMore] is true while a full page came back.
class AuditProvider extends ChangeNotifier {
  AuditProvider(this._service);

  final AuditService _service;
  static const _pageSize = 200;

  final List<AuditEvent> events = [];
  bool hasMore = false;

  String? hostId;
  String? type;

  /// 0 = all; 1 = today (since local midnight); otherwise events newer
  /// than [rangeDays] days.
  int rangeDays = 0;
  String search = '';

  String? get initError => _service.initError;
  bool get isAvailable => _service.isAvailable;

  AuditFilter get _filter {
    int? fromTs;
    if (rangeDays == 1) {
      final now = DateTime.now();
      fromTs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    } else if (rangeDays > 1) {
      fromTs = DateTime.now()
          .subtract(Duration(days: rangeDays))
          .millisecondsSinceEpoch;
    }
    return AuditFilter(
      hostId: hostId,
      type: type,
      fromTs: fromTs,
      search: search.trim().isEmpty ? null : search.trim(),
    );
  }

  void refresh() {
    events
      ..clear()
      ..addAll(_service.query(_filter, limit: _pageSize));
    hasMore = events.length == _pageSize;
    notifyListeners();
  }

  void loadMore() {
    if (events.isEmpty) {
      refresh();
      return;
    }
    // Keyset anchor (not OFFSET): rows recorded between refresh and
    // loadMore would shift an offset page → duplicates/skips.
    final last = events.last;
    final page = _service.query(_filter,
        limit: _pageSize,
        beforeTs: last.ts.millisecondsSinceEpoch,
        beforeId: last.id);
    events.addAll(page);
    hasMore = page.length == _pageSize;
    notifyListeners();
  }

  void setHost(String? id) {
    hostId = id;
    refresh();
  }

  void setType(String? t) {
    type = t;
    refresh();
  }

  void setRange(int days) {
    rangeDays = days;
    refresh();
  }

  void setSearch(String s) {
    search = s;
    refresh();
  }

  String exportCsv() => _service.exportCsv(_filter);
  String exportJson() => _service.exportJson(_filter);

  void clearAll() {
    _service.clearAll();
    refresh();
  }
}
