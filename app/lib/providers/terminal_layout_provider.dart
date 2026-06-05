// app/lib/providers/terminal_layout_provider.dart
import 'package:flutter/foundation.dart';

enum SplitLayout { single, horizontal, vertical, quad }

/// Which right-side workspace panel is open. Only one at a time.
enum SidePanel { none, snippets, terminalConfig }

class TerminalLayoutProvider extends ChangeNotifier {
  SplitLayout _layout = SplitLayout.single;
  bool _broadcastEnabled = false;
  bool _inputBarVisible = false;
  SidePanel _sidePanel = SidePanel.none;

  SplitLayout get layout => _layout;
  bool get broadcastEnabled => _broadcastEnabled;
  bool get inputBarVisible => _inputBarVisible;
  SidePanel get sidePanel => _sidePanel;
  bool get snippetsPanelVisible => _sidePanel == SidePanel.snippets;
  bool get configPanelVisible => _sidePanel == SidePanel.terminalConfig;

  int get paneCount => switch (_layout) {
    SplitLayout.single => 1,
    SplitLayout.horizontal => 2,
    SplitLayout.vertical => 2,
    SplitLayout.quad => 4,
  };

  void setLayout(SplitLayout layout) {
    _layout = layout;
    notifyListeners();
  }

  void toggleBroadcast() {
    _broadcastEnabled = !_broadcastEnabled;
    notifyListeners();
  }

  void toggleInputBar() {
    _inputBarVisible = !_inputBarVisible;
    notifyListeners();
  }

  /// Toggles [panel]: opens it, or closes it if already open.
  /// Opening one panel replaces whichever other panel was open.
  void toggleSidePanel(SidePanel panel) {
    _sidePanel = (_sidePanel == panel) ? SidePanel.none : panel;
    notifyListeners();
  }

  void toggleSnippetsPanel() => toggleSidePanel(SidePanel.snippets);
}
