// app/lib/providers/sftp_panel_provider.dart
import 'package:flutter/foundation.dart';
import '../models/sftp_entry.dart';
import '../util/entry_sort.dart';

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
  String _sortColumn = EntrySortColumn.name;
  bool _sortAscending = true;
  String? _anchor; // path of the range anchor
  List<SftpEntry>? _filtered;

  String get currentPath => _currentPath;
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward =>
      _historyIndex >= 0 && _historyIndex < _history.length - 1;
  List<SftpEntry> get entries => List.unmodifiable(_entries);
  Set<SftpEntry> get selectedEntries => Set.unmodifiable(_selected);
  bool get filterVisible => _filterVisible;
  String get filterQuery => _filterQuery;

  /// Column the listing is sorted by ([EntrySortColumn]); folders first.
  String get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  /// Entries matching the filter query (all entries when the query is
  /// empty), in display order. Cached until the entries, filter or sort
  /// change, so the file table sees the same list across selection changes.
  List<SftpEntry> get filteredEntries {
    if (_filtered case final cached?) return cached;
    final q = _filterQuery.toLowerCase();
    return _filtered = List.unmodifiable(_filterQuery.isEmpty
        ? _entries
        : _entries.where((e) => e.name.toLowerCase().contains(q)));
  }

  Comparator<SftpEntry> get _comparator => entryComparator<SftpEntry>(
        _sortColumn,
        ascending: _sortAscending,
        isDirectory: (e) => e.isDirectory,
        name: (e) => e.name,
        size: (e) => e.size,
        modified: (e) => e.modifiedAt,
        kind: (e) => e.kindLabel,
      );

  /// Re-sorts the listing by [column] (folders stay first).
  void setSort(String column, {required bool ascending}) {
    if (column == _sortColumn && ascending == _sortAscending) return;
    _sortColumn = column;
    _sortAscending = ascending;
    _entries.sort(_comparator);
    _filtered = null;
    notifyListeners();
  }

  void setFilterQuery(String query) {
    if (_filterQuery == query) return;
    _filterQuery = query;
    _filtered = null;
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
    _filtered = null;
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
    _anchor = null;
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    _historyIndex--;
    _currentPath = _history[_historyIndex];
    _selected.clear();
    _anchor = null;
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) return;
    _historyIndex++;
    _currentPath = _history[_historyIndex];
    _selected.clear();
    _anchor = null;
    notifyListeners();
  }

  void setEntries(List<SftpEntry> entries) {
    _entries = List.of(entries)..sort(_comparator);
    _filtered = null;
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
    _anchor = null;
    notifyListeners();
  }

  /// A file-table selection gesture on [entry]: plain selects only it,
  /// [additive] toggles it, [range] selects the visible run from the last
  /// anchor to it.
  void select(SftpEntry entry, {bool additive = false, bool range = false}) {
    final visible = filteredEntries;
    final (next, anchor) = applyTableSelection<SftpEntry, String>(
      visible: visible,
      keyOf: (e) => e.path,
      selected: {for (final e in _selected) e.path},
      anchor: _anchor,
      entry: entry,
      additive: additive,
      range: range,
    );
    _selected
      ..clear()
      ..addAll(visible.where((e) => next.contains(e.path)));
    _anchor = anchor;
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
