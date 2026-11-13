import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/local_entry.dart';
import '../util/entry_sort.dart';
import '../util/fs_error.dart';

enum LocalFilePanelLoadState { idle, loading, loaded, error }

class LocalFilePanelProvider extends ChangeNotifier {
  String _currentPath;
  List<LocalEntry> _entries = [];
  final Set<String> _selectedPaths = {};
  String _filterQuery = '';
  bool _filterVisible = false;
  bool _showHidden = false;
  final List<String> _history = [];
  int _historyIndex = -1;
  LocalFilePanelLoadState loadState = LocalFilePanelLoadState.idle;
  String? errorMessage;
  String _sortColumn = EntrySortColumn.name;
  bool _sortAscending = true;
  String? _anchorPath;
  List<LocalEntry>? _filtered;

  LocalFilePanelProvider() : _currentPath = _defaultPath() {
    _history.add(_currentPath);
    _historyIndex = 0;
  }

  LocalFilePanelProvider.forTest(String initialPath)
      : _currentPath = initialPath {
    _history.add(_currentPath);
    _historyIndex = 0;
  }

  static String _defaultPath() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    return Platform.environment['HOME'] ?? '/';
  }

  String get currentPath => _currentPath;
  bool get filterVisible => _filterVisible;
  bool get showHidden => _showHidden;
  String get filterQuery => _filterQuery;
  bool get canGoBack => _historyIndex > 0;
  bool get canGoForward => _historyIndex < _history.length - 1;

  /// Column the listing is sorted by ([EntrySortColumn]); folders first.
  String get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  /// Entries matching the filter query, in display order. Cached until the
  /// entries, filter or sort change, so the file table sees the same list
  /// across selection changes.
  List<LocalEntry> get filteredEntries {
    if (_filtered case final cached?) return cached;
    final q = _filterQuery.toLowerCase();
    return _filtered = List.unmodifiable(_filterQuery.isEmpty
        ? _entries
        : _entries.where((e) => e.name.toLowerCase().contains(q)));
  }

  Comparator<LocalEntry> get _comparator => entryComparator<LocalEntry>(
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
    _entries = List.of(_entries)..sort(_comparator);
    _filtered = null;
    notifyListeners();
  }

  bool isSelected(LocalEntry entry) => _selectedPaths.contains(entry.path);

  List<LocalEntry> get entries => List.unmodifiable(_entries);

  Set<LocalEntry> get selectedEntries {
    return _entries.where((e) => _selectedPaths.contains(e.path)).toSet();
  }

  /// True when every *visible* (filtered) entry is selected — drives the
  /// header select-all checkbox, mirroring SftpPanelProvider.
  bool get isAllSelected {
    final visible = filteredEntries;
    return visible.isNotEmpty &&
        visible.every((e) => _selectedPaths.contains(e.path));
  }

  // ── Navigation ──────────────────────────────────────────

  Future<void> loadDirectory(String path) async {
    pushPath(path);
    await _fetchDirectory(path);
  }

  void pushPath(String path) {
    if (_historyIndex == _history.length - 1) {
      // At the end of history: append normally so back still works.
      _history.add(path);
    } else {
      // In the middle (after goBack): keep current, clear forward, append new.
      _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(path);
    }
    _historyIndex = _history.length - 1;
    _currentPath = path;
    _selectedPaths.clear();
    _anchorPath = null;
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    _historyIndex--;
    _currentPath = _history[_historyIndex];
    _selectedPaths.clear();
    _anchorPath = null;
    notifyListeners();
    _fetchDirectory(_currentPath);
  }

  void goForward() {
    if (!canGoForward) return;
    _historyIndex++;
    _currentPath = _history[_historyIndex];
    _selectedPaths.clear();
    _anchorPath = null;
    notifyListeners();
    _fetchDirectory(_currentPath);
  }

  void navigateUp() {
    final parent = p.dirname(_currentPath);
    if (parent == _currentPath) return;
    loadDirectory(parent);
  }

  Future<void> reload() => _fetchDirectory(_currentPath);

  int _fetchToken = 0;

  Future<void> _fetchDirectory(String path) async {
    final token = ++_fetchToken;
    loadState = LocalFilePanelLoadState.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final dir = Directory(path);
      final entities = await dir.list().toList();
      if (token != _fetchToken) return; // a newer fetch superseded us
      final entries = <LocalEntry>[];
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (!_showHidden && name.startsWith('.')) continue;
        final stat = await entity.stat();
        entries.add(LocalEntry(
          name: name,
          path: entity.path,
          isDirectory: entity is Directory,
          size: stat.size,
          modifiedAt: stat.modified,
          permissions: (entity is Directory ? 'd' : '-') + stat.modeString(),
          // notFound stats (entry raced a delete) report mode 0 — keep null
          // so the permissions dialog treats it as unknown, not 000.
          mode:
              stat.type == FileSystemEntityType.notFound ? null : stat.mode,
        ));
      }
      if (token != _fetchToken) return;
      entries.sort(_comparator);
      _entries = entries;
      _filtered = null;
      loadState = LocalFilePanelLoadState.loaded;
    } catch (e) {
      if (token != _fetchToken) return;
      loadState = LocalFilePanelLoadState.error;
      errorMessage = describeFileSystemError(e, path: path);
    }
    notifyListeners();
  }

  // ── Selection ───────────────────────────────────────────

  void toggleSelection(LocalEntry entry) {
    if (_selectedPaths.contains(entry.path)) {
      _selectedPaths.remove(entry.path);
    } else {
      _selectedPaths.add(entry.path);
    }
    notifyListeners();
  }

  void selectOnly(LocalEntry entry) {
    _selectedPaths
      ..clear()
      ..add(entry.path);
    notifyListeners();
  }

  void deselectAll() => clearSelection();

  void clearSelection() {
    _selectedPaths.clear();
    _anchorPath = null;
    notifyListeners();
  }

  /// A file-table selection gesture on [entry]: plain selects only it,
  /// [additive] toggles it, [range] selects the visible run from the last
  /// anchor to it.
  void select(LocalEntry entry, {bool additive = false, bool range = false}) {
    final (next, anchor) = applyTableSelection<LocalEntry, String>(
      visible: filteredEntries,
      keyOf: (e) => e.path,
      selected: _selectedPaths,
      anchor: _anchorPath,
      entry: entry,
      additive: additive,
      range: range,
    );
    _selectedPaths
      ..clear()
      ..addAll(next);
    _anchorPath = anchor;
    notifyListeners();
  }

  void selectAll() {
    for (final entry in filteredEntries) {
      _selectedPaths.add(entry.path);
    }
    notifyListeners();
  }

  // ── Filter ──────────────────────────────────────────────

  void toggleFilterVisible() {
    _filterVisible = !_filterVisible;
    if (!_filterVisible) _filterQuery = '';
    _filtered = null;
    notifyListeners();
  }

  void toggleShowHidden() {
    _showHidden = !_showHidden;
    notifyListeners();
    _fetchDirectory(_currentPath);
  }

  void setFilterQuery(String query) {
    if (_filterQuery == query) return;
    _filterQuery = query;
    _filtered = null;
    // Selection must stay within what the user can see (parity with
    // SftpPanelProvider): drop selected paths the new filter hides.
    if (query.isNotEmpty) {
      final visible = filteredEntries.map((e) => e.path).toSet();
      _selectedPaths.retainWhere(visible.contains);
    }
    notifyListeners();
  }

  // ── Test helpers ────────────────────────────────────────

  void setEntriesForTest(List<LocalEntry> entries) {
    _entries = List.of(entries);
    _filtered = null;
    loadState = LocalFilePanelLoadState.loaded;
    notifyListeners();
  }
}
