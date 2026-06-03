// app/lib/providers/terminal_layout_provider.dart
import 'package:flutter/foundation.dart';

enum SplitLayout { single, horizontal, vertical, quad }

class TerminalLayoutProvider extends ChangeNotifier {
  SplitLayout _layout = SplitLayout.single;
  bool _broadcastEnabled = false;
  bool _inputBarVisible = false;
  bool _snippetsPanelVisible = false;

  SplitLayout get layout => _layout;
  bool get broadcastEnabled => _broadcastEnabled;
  bool get inputBarVisible => _inputBarVisible;
  bool get snippetsPanelVisible => _snippetsPanelVisible;

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

  void toggleSnippetsPanel() {
    _snippetsPanelVisible = !_snippetsPanelVisible;
    notifyListeners();
  }
}
