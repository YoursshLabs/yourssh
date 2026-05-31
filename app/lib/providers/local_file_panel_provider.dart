import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/local_entry.dart';

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

  List<LocalEntry> get filteredEntries {
    if (_filterQuery.isEmpty) return List.unmodifiable(_entries);
    final q = _filterQuery.toLowerCase();
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Set<LocalEntry> get selectedEntries {
    return _entries.where((e) => _selectedPaths.contains(e.path)).toSet();
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
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    _historyIndex--;
    _currentPath = _history[_historyIndex];
    _selectedPaths.clear();
    notifyListeners();
    _fetchDirectory(_currentPath);
  }

  void goForward() {
    if (!canGoForward) return;
    _historyIndex++;
    _currentPath = _history[_historyIndex];
    _selectedPaths.clear();
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
        ));
      }
      if (token != _fetchToken) return;
      entries.sort((a, b) => a.sortKey.compareTo(b.sortKey));
      _entries = entries;
      loadState = LocalFilePanelLoadState.loaded;
    } catch (e) {
      if (token != _fetchToken) return;
      loadState = LocalFilePanelLoadState.error;
      errorMessage = e.toString();
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

  void clearSelection() {
    _selectedPaths.clear();
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
    notifyListeners();
  }

  // ── Test helpers ────────────────────────────────────────

  void setEntriesForTest(List<LocalEntry> entries) {
    _entries = List.of(entries);
    loadState = LocalFilePanelLoadState.loaded;
    notifyListeners();
  }
}
