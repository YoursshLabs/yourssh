import 'package:flutter/foundation.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';

/// Dialog-scoped state for one bulk run. Created and disposed by the
/// dialog that shows it — deliberately NOT registered in main.dart's
/// MultiProvider: the run lives only as long as the dialog and nothing
/// outside consumes it.
class BulkRunController extends ChangeNotifier {
  final BulkActionService _service;
  final List<Host> hosts;

  BulkRunController({required BulkActionService service, required this.hosts})
      : _service = service; // ignore: prefer_initializing_formals

  final Map<String, BulkHostResult> _results = {}; // hostId → latest
  BulkCancelToken? _token;
  bool _running = false;
  bool _disposed = false;

  bool get isRunning => _running;
  bool get hasRun => _results.isNotEmpty;

  /// Latest result per host, in the order the run was started with.
  List<BulkHostResult> get results => [
        for (final h in hosts)
          if (_results[h.id] != null) _results[h.id]!,
      ];

  int countOf(BulkHostStatus status) =>
      results.where((r) => r.status == status).length;

  Future<void> runCommand(String command) =>
      _start((token) => _service.runCommand(hosts, command,
          onUpdate: _onUpdate, token: token));

  Future<void> pushFiles(List<BulkPushSource> sources, String remoteDir) =>
      _start((token) => _service.pushFiles(hosts, sources, remoteDir,
          onUpdate: _onUpdate, token: token));

  Future<void> _start(
      Future<void> Function(BulkCancelToken token) run) async {
    if (_running) return;
    _running = true;
    final token = BulkCancelToken();
    _token = token;
    for (final h in hosts) {
      _results[h.id] = BulkHostResult(host: h, status: BulkHostStatus.pending);
    }
    _safeNotify();
    try {
      await run(token);
    } finally {
      _running = false;
      _safeNotify();
    }
  }

  void _onUpdate(BulkHostResult r) {
    _results[r.host.id] = r;
    _safeNotify();
  }

  void cancel() => _token?.cancel();

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
