import 'dart:collection';

class CommandHistory {
  final int maxSize;
  final ListQueue<String> _entries;
  int _cursor = -1;

  CommandHistory({required this.maxSize}) : _entries = ListQueue();

  List<String> get entries => _entries.toList();

  void add(String command) {
    if (command.trim().isEmpty) return;
    if (_entries.isNotEmpty && _entries.first == command) return;
    _entries.addFirst(command);
    if (_entries.length > maxSize) _entries.removeLast();
    _cursor = -1;
  }

  void resetCursor() => _cursor = -1;

  String? navigateUp() {
    if (_entries.isEmpty) return null;
    _cursor = (_cursor + 1).clamp(0, _entries.length - 1);
    return _entries.elementAt(_cursor);
  }

  String? navigateDown() {
    if (_cursor <= 0) {
      _cursor = -1;
      return null;
    }
    _cursor--;
    return _entries.elementAt(_cursor);
  }

  Map<String, dynamic> toJson() => {
    'entries': _entries.toList(),
    'maxSize': maxSize,
  };

  factory CommandHistory.fromJson(Map<String, dynamic> json, {required int maxSize}) {
    final h = CommandHistory(maxSize: maxSize);
    final entries = (json['entries'] as List<dynamic>).cast<String>();
    for (final e in entries.reversed) {
      h._entries.addFirst(e);
    }
    return h;
  }
}
