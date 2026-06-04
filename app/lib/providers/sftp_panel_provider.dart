// app/lib/providers/sftp_panel_provider.dart
import 'package:flutter/foundation.dart';
import '../models/sftp_entry.dart';

enum SftpPanelLoadState { idle, loading, loaded, error }

class SftpPanelProvider extends ChangeNotifier {
  String _currentPath = '/';
  List<SftpEntry> _entries = [];
  final Set<SftpEntry> _selected = {};
  String _filterQuery = '';
  bool _filterVisible = false;
  SftpPanelLoadState loadState = SftpPanelLoadState.idle;
  String? errorMessage;

  String get currentPath => _currentPath;
  List<SftpEntry> get entries => List.unmodifiable(_entries);
  Set<SftpEntry> get selectedEntries => Set.unmodifiable(_selected);
  bool get filterVisible => _filterVisible;
  String get filterQuery => _filterQuery;

  /// Entries matching the filter query (all entries when the query is empty).
  List<SftpEntry> get filteredEntries {
    if (_filterQuery.isEmpty) return List.unmodifiable(_entries);
    final q = _filterQuery.toLowerCase();
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  void setFilterQuery(String query) {
    _filterQuery = query;
    notifyListeners();
  }

  void toggleFilterVisible() {
    _filterVisible = !_filterVisible;
    if (!_filterVisible) _filterQuery = '';
    notifyListeners();
  }

  void setPath(String path) {
    _currentPath = path;
    _selected.clear();
    notifyListeners();
  }

  void setEntries(List<SftpEntry> entries) {
    _entries = List.of(entries)..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    notifyListeners();
  }

  void toggleSelection(SftpEntry entry) {
    if (_selected.contains(entry)) {
      _selected.remove(entry);
    } else {
      _selected.add(entry);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  void selectAll() {
    for (final entry in _entries) {
      _selected.add(entry);
    }
    notifyListeners();
  }

  void deselectAll() => clearSelection();

  bool get isAllSelected => _entries.isNotEmpty && _selected.length == _entries.length;

  void navigateUp() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _currentPath = parts.isEmpty || (parts.length == 1 && parts.first.isEmpty)
        ? '/'
        : parts.join('/');
    _selected.clear();
    notifyListeners();
  }

  void setLoadState(SftpPanelLoadState state, {String? error}) {
    loadState = state;
    errorMessage = error;
    notifyListeners();
  }
}
