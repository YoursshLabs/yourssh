import 'package:flutter/foundation.dart';
import '../models/shell_session_state.dart';
import '../services/shell_integration_service.dart';

class ShellIntegrationProvider extends ChangeNotifier {
  ShellIntegrationProvider([ShellIntegrationService? service])
      : _service = service ?? ShellIntegrationService();

  final ShellIntegrationService _service;
  final Map<String, ShellSessionState> _states = {};
  // Per-session change counter so consumers can `context.select` on their own
  // session and avoid rebuilding when an unrelated session emits OSC.
  final Map<String, int> _revisions = {};

  ShellSessionState? maybeStateFor(String id) => _states[id];
  String? cwdFor(String id) => _states[id]?.cwd;
  int revisionFor(String id) => _revisions[id] ?? 0;

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
      case ShellOscKind.finished:
        st.onFinished(ev.exitCode);
    }
    _revisions[sessionId] = revisionFor(sessionId) + 1;
    notifyListeners();
  }

  void clear(String sessionId) {
    final had = _states.remove(sessionId) != null;
    _revisions.remove(sessionId);
    if (had) notifyListeners();
  }
}
