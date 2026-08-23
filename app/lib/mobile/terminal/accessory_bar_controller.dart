import 'package:flutter/foundation.dart';

/// Sticky Ctrl/Alt state for the mobile terminal accessory bar. Modifiers are
/// one-shot: arming sets the flag, the next emitted key consumes and clears it
/// (mstsc/Termux-style). A [ChangeNotifier] so the bar highlights armed keys.
class AccessoryBarController extends ChangeNotifier {
  bool _ctrl = false;
  bool _alt = false;

  bool get ctrlArmed => _ctrl;
  bool get altArmed => _alt;

  void armCtrl() {
    _ctrl = !_ctrl;
    notifyListeners();
  }

  void armAlt() {
    _alt = !_alt;
    notifyListeners();
  }

  /// Returns the currently-armed modifiers and clears them (one-shot).
  ({bool ctrl, bool alt}) consumeModifiers() {
    final m = (ctrl: _ctrl, alt: _alt);
    if (_ctrl || _alt) {
      _ctrl = false;
      _alt = false;
      notifyListeners();
    }
    return m;
  }
}
