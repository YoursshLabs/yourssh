/// Minimal interface for anything that occupies a top-tab-bar slot.
/// `TerminalSession` (SSH + local PTY) and `RdpSession` both implement this.
abstract class AppSession {
  String get id;

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
}
