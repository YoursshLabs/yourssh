// app/lib/providers/local_session_provider.dart
import 'package:flutter/foundation.dart';
import '../models/local_session.dart';
import '../services/local_shell_service.dart';

class LocalSessionProvider extends ChangeNotifier {
  final LocalShellService _service = LocalShellService();
  final List<LocalSession> _sessions = [];
  String? _activeId;

  List<LocalSession> get sessions => List.unmodifiable(_sessions);
  LocalSession? get activeSession =>
      _sessions.where((s) => s.id == _activeId).firstOrNull;

  Future<void> newSession() async {
    final session = await _service.openShell();
    _sessions.add(session);
    _activeId = session.id;
    notifyListeners();
  }

  void setActive(String id) {
    _activeId = id;
    notifyListeners();
  }

  void closeSession(String id) {
    _service.closeSession(id);
    _sessions.removeWhere((s) => s.id == id);
    if (_activeId == id) {
      _activeId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    notifyListeners();
  }
}
