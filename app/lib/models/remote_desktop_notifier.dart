import 'package:flutter/foundation.dart';

/// Splits a remote-desktop session's change notifications in two.
///
/// The session itself ([ChangeNotifier.notifyListeners]) still fires on every
/// frame, for its workspace and frame painter. [stateChanges] fires only when
/// something other than the picture changes: status, message, desktop size,
/// certificate, or the first decoded frame.
///
/// [SessionProvider] forwards [stateChanges], not the session, so a streaming
/// desktop does not rebuild every SessionProvider listener (MainScreen, the
/// tab bar, the hosts dashboard, the workspace-save debounce) on each frame.
mixin RemoteDesktopNotifier on ChangeNotifier {
  final _state = _StateNotifier();

  /// Fires on state changes only, never on a frame-only repaint.
  Listenable get stateChanges => _state;

  /// Notifies the session's listeners and [stateChanges].
  @protected
  void notifyState() {
    notifyListeners();
    _state.notify();
  }
}

class _StateNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
