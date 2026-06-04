import 'package:xterm/xterm.dart';

/// Common interface for anything that appears as a tab in the global top tab
/// bar: remote SSH sessions and local PTY shells. Consumers that only need
/// tab behavior (label, color, pin, terminal) depend on this; SSH-only
/// features branch on the concrete type.
abstract class TerminalSession {
  String get id;
  Terminal get terminal;

  /// Label shown on the session tab.
  String get tabLabel;

  /// User rename — null means "use the default label".
  String? get customLabel;
  set customLabel(String? value);

  /// Tab color tag as #RRGGBB hex, null = none.
  String? get colorTag;
  set colorTag(String? value);

  bool get isPinned;
  set isPinned(bool value);

  bool get isLocal;

  /// Folder name recordings of this session are grouped under
  /// (`{recordingsPath}/{recordingFolder}/session_*.cast`).
  String get recordingFolder;

  /// Title written into the asciicast header.
  String get recordingTitle;
}
