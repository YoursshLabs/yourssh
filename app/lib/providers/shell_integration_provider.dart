import 'package:flutter/foundation.dart';
import '../models/shell_session_state.dart';
import '../services/shell_integration_service.dart';

class ShellIntegrationProvider extends ChangeNotifier {
  ShellIntegrationProvider([ShellIntegrationService? service])
      : _service = service ?? ShellIntegrationService();

  final ShellIntegrationService _service;
  final Map<String, ShellSessionState> _states = {};

  ShellSessionState? maybeStateFor(String id) => _states[id];
  String? cwdFor(String id) => _states[id]?.cwd;

  String buildInjectionScript() => _service.buildInjectionScript();

  /// [absoluteCursorY] is `terminal.buffer.absoluteCursorY` captured by the
  /// caller at marker time (kept out of this class so it stays testable).
  void handleOsc(
      String sessionId, String code, List<String> args, int absoluteCursorY) {
    final ev = _service.parseOsc(code, args);
    if (ev == null) return;
    final st = _states.putIfAbsent(sessionId, ShellSessionState.new);
    switch (ev.kind) {
      case ShellOscKind.cwd:
        st.setCwd(ev.cwd!);
      case ShellOscKind.promptStart:
        st.onPromptStart(absoluteCursorY);
      case ShellOscKind.exec:
        st.onExec();
      case ShellOscKind.finished:
        st.onFinished(ev.exitCode);
    }
    notifyListeners();
  }

  void clear(String sessionId) {
    if (_states.remove(sessionId) != null) notifyListeners();
  }
}
