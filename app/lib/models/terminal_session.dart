import 'package:xterm/xterm.dart';

import 'app_session.dart';

export 'app_session.dart';

/// Terminal-bearing session (SSH or local PTY shell). Extends [AppSession]
/// with terminal-specific fields. Code that works with all tab types should
/// depend on [AppSession]; code that needs the terminal depends on this.
abstract class TerminalSession extends AppSession {
  Terminal get terminal;
  bool get isLocal;

  /// Folder name recordings of this session are grouped under
  /// (`{recordingsPath}/{recordingFolder}/session_*.cast`).
  String get recordingFolder;

  /// Title written into the asciicast header.
  String get recordingTitle;
}
