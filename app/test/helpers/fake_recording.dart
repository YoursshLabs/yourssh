import 'package:yourssh/models/terminal_session.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/services/recording_service.dart';

/// Recording state a test controls directly (no files are written).
class FakeRecording extends RecordingProvider {
  FakeRecording() : super(RecordingService(), getPath: () => '');

  final Set<String> active = {};
  Duration elapsed = Duration.zero;

  @override
  bool isRecording(String sessionId) => active.contains(sessionId);

  @override
  Duration? recordingElapsed(String sessionId) =>
      active.contains(sessionId) ? elapsed : null;

  final List<String> started = [];
  final List<String> stopped = [];

  @override
  Future<void> startRecording(TerminalSession session) async {
    started.add(session.id);
    setRecording(session.id, true);
  }

  @override
  Future<void> stopRecording(String sessionId) async {
    stopped.add(sessionId);
    setRecording(sessionId, false);
  }

  void setRecording(String sessionId, bool on) {
    on ? active.add(sessionId) : active.remove(sessionId);
    notifyListeners();
  }
}
