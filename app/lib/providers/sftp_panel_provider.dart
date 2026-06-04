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
  // Back/forward history (mirrors LocalFilePanelProvider). Starts empty:
  // the first setPath (the panel's initial load) seeds it, so goBack never
  // leads to a path the user never visited.
  final List<String> _history = [];
  int _historyIndex = -1;
  SftpPanelLoadState loadState = SftpPanelLoadState.idle;
  String? errorMessage;

  String get currentPath => _currentPath;
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward =>
      _historyIndex >= 0 && _historyIndex < _history.length - 1;
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
    if (_filterQuery == query) return;
    _filterQuery = query;
    // Selection must stay within what the user can see: anything the new
    // filter hides is dropped, so bulk actions (Delete/Rename) can never
    // touch entries that were selected and then filtered out of view.
    if (query.isNotEmpty) {
      final visible = filteredEntries.toSet();
      _selected.retainWhere(visible.contains);
    }
    notifyListeners();
  }

  void toggleFilterVisible() {
    _filterVisible = !_filterVisible;
    if (!_filterVisible) _filterQuery = '';
    notifyListeners();
  }

  /// Sets the current path and records it in the back/forward history.
  /// Re-setting the path already at the history cursor (Refresh) keeps the
  /// history untouched; navigating after goBack drops the forward branch.
  void setPath(String path) {
    if (_historyIndex < 0 || _history[_historyIndex] != path) {
      _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(path);
      _historyIndex = _history.length - 1;
    }
    _currentPath = path;
    _selected.clear();
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    _historyIndex--;
    _currentPath = _history[_historyIndex];
    _selected.clear();
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) return;
    _historyIndex++;
    _currentPath = _history[_historyIndex];
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

  /// Selects every *visible* entry — entries hidden by the filter are never
  /// selected (mirrors LocalFilePanelProvider).
  void selectAll() {
    for (final entry in filteredEntries) {
      _selected.add(entry);
    }
    notifyListeners();
  }

  void deselectAll() => clearSelection();

  bool get isAllSelected {
    final visible = filteredEntries;
    return visible.isNotEmpty && visible.every(_selected.contains);
  }

  void setLoadState(SftpPanelLoadState state, {String? error}) {
    loadState = state;
    errorMessage = error;
    notifyListeners();
  }
}
