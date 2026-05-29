// app/lib/providers/terminal_layout_provider.dart
import 'package:flutter/foundation.dart';

enum SplitLayout { single, horizontal, vertical, quad }

class TerminalLayoutProvider extends ChangeNotifier {
  SplitLayout _layout = SplitLayout.single;
  bool _broadcastEnabled = false;

  SplitLayout get layout => _layout;
  bool get broadcastEnabled => _broadcastEnabled;

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
}
