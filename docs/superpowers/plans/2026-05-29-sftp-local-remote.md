# SFTP Local-Remote Dual Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace both-remote SFTP panels with left=local-machine browser, right=remote SSH panel (empty-state until host selected), plus a center transfer bar with ←/→ buttons and drag-and-drop.

**Architecture:** Create `LocalEntry` model + `LocalFilePanelProvider` + `LocalFilePanel` widget for the left panel. Update `SftpPanel` to accept nullable host (shows empty state when null) and an external `SftpPanelProvider`. `DualPanelSftpScreen` owns both providers, renders the transfer bar, and wires drag-and-drop.

**Tech Stack:** Flutter, dart:io (local fs), dartssh2 (remote SFTP), provider package, path package

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `app/lib/models/local_entry.dart` | Local filesystem entry data class |
| Create | `app/lib/providers/local_file_panel_provider.dart` | Local panel state: path, entries, selection, filter, history |
| Create | `app/lib/widgets/local_file_panel.dart` | Local browser widget: header, breadcrumb, file list, Filter, Actions |
| Modify | `app/lib/widgets/sftp_panel.dart` | Accept external provider + nullable host + empty state + draggable rows |
| Modify | `app/lib/services/sftp_transfer_service.dart` | Add copyLocalToRemote + copyRemoteToLocal |
| Modify | `app/lib/widgets/dual_panel_sftp_screen.dart` | Left=local, right=remote, transfer bar, drag targets |
| Create | `app/test/models/local_entry_test.dart` | Unit tests for LocalEntry |
| Create | `app/test/providers/local_file_panel_provider_test.dart` | Unit tests for provider state logic |

---

## Task 1: LocalEntry model

**Files:**
- Create: `app/lib/models/local_entry.dart`
- Create: `app/test/models/local_entry_test.dart`

- [x] **Step 1: Write the failing test**

Create `app/test/models/local_entry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/local_entry.dart';

void main() {
  group('LocalEntry.formattedSize', () {
    LocalEntry make(int size) => LocalEntry(
          name: 'f',
          path: '/f',
          isDirectory: false,
          size: size,
          modifiedAt: DateTime(2024),
          permissions: '-rw-r--r--',
        );

    test('bytes', () => expect(make(500).formattedSize, '500 B'));
    test('KB', () => expect(make(5120).formattedSize, '5.0 KB'));
    test('MB', () => expect(make(5 * 1024 * 1024).formattedSize, '5.0 MB'));
    test('directory shows dash', () {
      final dir = LocalEntry(
        name: 'd',
        path: '/d',
        isDirectory: true,
        size: 0,
        modifiedAt: DateTime(2024),
        permissions: 'drwxr-xr-x',
      );
      expect(dir.formattedSize, '-');
    });
  });

  group('LocalEntry.sortKey', () {
    test('directories sort before files', () {
      final dir = LocalEntry(
          name: 'z', path: '/z', isDirectory: true, size: 0,
          modifiedAt: DateTime(2024), permissions: 'drwxr-xr-x');
      final file = LocalEntry(
          name: 'a', path: '/a', isDirectory: false, size: 0,
          modifiedAt: DateTime(2024), permissions: '-rw-r--r--');
      expect(dir.sortKey.compareTo(file.sortKey), lessThan(0));
    });
  });

  group('LocalEntry.extension', () {
    test('extracts extension', () {
      final e = LocalEntry(
          name: 'main.dart', path: '/main.dart', isDirectory: false,
          size: 0, modifiedAt: DateTime(2024), permissions: '-rw-r--r--');
      expect(e.extension, 'dart');
    });
    test('empty for directory', () {
      final e = LocalEntry(
          name: 'src', path: '/src', isDirectory: true,
          size: 0, modifiedAt: DateTime(2024), permissions: 'drwxr-xr-x');
      expect(e.extension, '');
    });
    test('empty for no extension', () {
      final e = LocalEntry(
          name: 'Makefile', path: '/Makefile', isDirectory: false,
          size: 0, modifiedAt: DateTime(2024), permissions: '-rw-r--r--');
      expect(e.extension, '');
    });
  });

  group('LocalEntry.kindLabel', () {
    test('folder', () {
      final e = LocalEntry(
          name: 'd', path: '/d', isDirectory: true, size: 0,
          modifiedAt: DateTime(2024), permissions: 'drwxr-xr-x');
      expect(e.kindLabel, 'folder');
    });
    test('known extension', () {
      final e = LocalEntry(
          name: 'f.dart', path: '/f.dart', isDirectory: false, size: 0,
          modifiedAt: DateTime(2024), permissions: '-rw-r--r--');
      expect(e.kindLabel, 'dart');
    });
    test('unknown extension falls back to document', () {
      final e = LocalEntry(
          name: 'foo.xyz', path: '/foo.xyz', isDirectory: false, size: 0,
          modifiedAt: DateTime(2024), permissions: '-rw-r--r--');
      expect(e.kindLabel, 'document');
    });
  });
}
```

- [x] **Step 2: Run test — expect compile failure (class not defined yet)**

```bash
cd app && flutter test test/models/local_entry_test.dart
```

Expected: error — `LocalEntry` not found.

- [x] **Step 3: Create `app/lib/models/local_entry.dart`**

```dart
class LocalEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;
  final String permissions;

  const LocalEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    required this.permissions,
  });

  String get extension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get formattedSize {
    if (isDirectory) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get sortKey => (isDirectory ? '0' : '1') + name.toLowerCase();

  String get kindLabel {
    if (isDirectory) return 'folder';
    if (extension.isEmpty) return 'document';
    return extension;
  }
}
```

- [x] **Step 4: Run test — expect pass**

```bash
cd app && flutter test test/models/local_entry_test.dart
```

Expected: All tests pass.

- [x] **Step 5: Commit**

```bash
git add app/lib/models/local_entry.dart app/test/models/local_entry_test.dart
git commit -m "feat: add LocalEntry model for local filesystem browsing"
```

---

## Task 2: LocalFilePanelProvider

**Files:**
- Create: `app/lib/providers/local_file_panel_provider.dart`
- Create: `app/test/providers/local_file_panel_provider_test.dart`

- [x] **Step 1: Write the failing tests**

Create directory: `app/test/providers/`

Create `app/test/providers/local_file_panel_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/local_entry.dart';
import 'package:yourssh/providers/local_file_panel_provider.dart';

LocalEntry _entry(String name, {bool isDir = false}) => LocalEntry(
      name: name,
      path: '/$name',
      isDirectory: isDir,
      size: 100,
      modifiedAt: DateTime(2024),
      permissions: isDir ? 'drwxr-xr-x' : '-rw-r--r--',
    );

void main() {
  late LocalFilePanelProvider provider;

  setUp(() {
    provider = LocalFilePanelProvider.forTest('/home/user');
  });

  group('filter', () {
    test('empty query returns all entries', () {
      provider.setEntriesForTest([_entry('main.dart'), _entry('README.md')]);
      expect(provider.filteredEntries.length, 2);
    });

    test('query filters case-insensitively', () {
      provider.setEntriesForTest([_entry('main.dart'), _entry('README.md')]);
      provider.setFilterQuery('main');
      expect(provider.filteredEntries.length, 1);
      expect(provider.filteredEntries.first.name, 'main.dart');
    });

    test('clearing query restores all entries', () {
      provider.setEntriesForTest([_entry('main.dart'), _entry('README.md')]);
      provider.setFilterQuery('main');
      provider.setFilterQuery('');
      expect(provider.filteredEntries.length, 2);
    });
  });

  group('selection', () {
    test('toggleSelection adds entry', () {
      final e = _entry('a');
      provider.setEntriesForTest([e]);
      provider.toggleSelection(e);
      expect(provider.selectedEntries.length, 1);
    });

    test('toggleSelection removes already-selected entry', () {
      final e = _entry('a');
      provider.setEntriesForTest([e]);
      provider.toggleSelection(e);
      provider.toggleSelection(e);
      expect(provider.selectedEntries.isEmpty, true);
    });

    test('selectOnly replaces existing selection', () {
      final a = _entry('a');
      final b = _entry('b');
      provider.setEntriesForTest([a, b]);
      provider.toggleSelection(a);
      provider.selectOnly(b);
      expect(provider.selectedEntries.length, 1);
      expect(provider.selectedEntries.first.name, 'b');
    });

    test('clearSelection empties the set', () {
      final e = _entry('a');
      provider.setEntriesForTest([e]);
      provider.toggleSelection(e);
      provider.clearSelection();
      expect(provider.selectedEntries.isEmpty, true);
    });
  });

  group('history navigation', () {
    test('starts with initial path, canGoBack false', () {
      expect(provider.currentPath, '/home/user');
      expect(provider.canGoBack, false);
      expect(provider.canGoForward, false);
    });

    test('pushPath enables canGoBack', () {
      provider.pushPath('/home/user/Documents');
      expect(provider.currentPath, '/home/user/Documents');
      expect(provider.canGoBack, true);
      expect(provider.canGoForward, false);
    });

    test('goBack returns to previous path', () {
      provider.pushPath('/home/user/Documents');
      provider.goBack();
      expect(provider.currentPath, '/home/user');
      expect(provider.canGoBack, false);
      expect(provider.canGoForward, true);
    });

    test('goForward replays forward', () {
      provider.pushPath('/home/user/Documents');
      provider.goBack();
      provider.goForward();
      expect(provider.currentPath, '/home/user/Documents');
      expect(provider.canGoForward, false);
    });

    test('pushPath from middle truncates forward history', () {
      provider.pushPath('/a');
      provider.pushPath('/b');
      provider.goBack(); // at /a
      provider.pushPath('/c'); // truncates /b
      expect(provider.canGoForward, false);
      provider.goBack();
      expect(provider.currentPath, '/home/user');
    });
  });

  group('filterVisible toggle', () {
    test('toggle shows filter', () {
      expect(provider.filterVisible, false);
      provider.toggleFilterVisible();
      expect(provider.filterVisible, true);
    });

    test('hiding filter resets query', () {
      provider.toggleFilterVisible();
      provider.setFilterQuery('foo');
      provider.toggleFilterVisible(); // hide
      expect(provider.filterVisible, false);
      expect(provider.filterQuery, '');
    });
  });
}
```

- [x] **Step 2: Run test — expect compile failure**

```bash
cd app && flutter test test/providers/local_file_panel_provider_test.dart
```

Expected: error — `LocalFilePanelProvider` not found.

- [x] **Step 3: Create `app/lib/providers/local_file_panel_provider.dart`**

```dart
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
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(path);
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

  Future<void> _fetchDirectory(String path) async {
    loadState = LocalFilePanelLoadState.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final dir = Directory(path);
      final entities = await dir.list().toList();
      final entries = <LocalEntry>[];
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
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
      entries.sort((a, b) => a.sortKey.compareTo(b.sortKey));
      _entries = entries;
      loadState = LocalFilePanelLoadState.loaded;
    } catch (e) {
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

  // ── Filter ──────────────────────────────────────────────

  void toggleFilterVisible() {
    _filterVisible = !_filterVisible;
    if (!_filterVisible) _filterQuery = '';
    notifyListeners();
  }

  void setFilterQuery(String query) {
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
```

- [x] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/providers/local_file_panel_provider_test.dart
```

Expected: All tests pass.

- [x] **Step 5: Commit**

```bash
git add app/lib/providers/local_file_panel_provider.dart \
        app/test/providers/local_file_panel_provider_test.dart
git commit -m "feat: add LocalFilePanelProvider with history, filter, selection"
```

---

## Task 3: LocalFilePanel widget

**Files:**
- Create: `app/lib/widgets/local_file_panel.dart`

- [x] **Step 1: Create `app/lib/widgets/local_file_panel.dart`**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/local_entry.dart';
import '../providers/local_file_panel_provider.dart';

class LocalFilePanel extends StatefulWidget {
  final LocalFilePanelProvider provider;

  const LocalFilePanel({super.key, required this.provider});

  @override
  State<LocalFilePanel> createState() => _LocalFilePanelState();
}

class _LocalFilePanelState extends State<LocalFilePanel> {
  @override
  void initState() {
    super.initState();
    widget.provider.reload();
  }

  // ── Actions ─────────────────────────────────────────────

  Future<void> _createFolder() async {
    final name = await _showInputDialog(context, title: 'New Folder', hint: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    final newPath = p.join(widget.provider.currentPath, name.trim());
    try {
      await Directory(newPath).create();
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('Failed to create folder: $e');
    }
  }

  Future<void> _renameSelected() async {
    final selected = widget.provider.selectedEntries;
    if (selected.length != 1) return;
    final entry = selected.first;
    final newName = await _showInputDialog(context,
        title: 'Rename', hint: 'New name', initial: entry.name);
    if (newName == null || newName.trim().isEmpty || newName.trim() == entry.name) return;
    final newPath = p.join(p.dirname(entry.path), newName.trim());
    try {
      if (entry.isDirectory) {
        await Directory(entry.path).rename(newPath);
      } else {
        await File(entry.path).rename(newPath);
      }
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('Rename failed: $e');
    }
  }

  Future<void> _deleteSelected() async {
    final selected = widget.provider.selectedEntries.toList();
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete', style: TextStyle(color: Color(0xFFD4D4D4))),
        content: Text(
          'Delete ${selected.length} item(s)? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final entry in selected) {
        if (entry.isDirectory) {
          await Directory(entry.path).delete(recursive: true);
        } else {
          await File(entry.path).delete();
        }
      }
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('Delete failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF2A1A1A)),
    );
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<LocalFilePanelProvider>(
        builder: (context, prov, _) => Column(
          children: [
            _buildHeader(prov),
            if (prov.filterVisible) _buildFilterBar(prov),
            _buildBreadcrumb(prov),
            _buildColumnHeader(),
            Expanded(child: _buildContent(prov)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalFilePanelProvider prov) {
    return Container(
      height: 40,
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.computer, size: 14, color: Color(0xFF888888)),
          const SizedBox(width: 6),
          const Text('Local',
              style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          // Filter button
          _HeaderButton(
            label: 'Filter',
            active: prov.filterVisible,
            onTap: prov.toggleFilterVisible,
          ),
          const SizedBox(width: 6),
          // Actions menu
          PopupMenuButton<String>(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFF2A2A2A))),
            tooltip: '',
            offset: const Offset(0, 36),
            onSelected: (v) {
              if (v == 'new_folder') _createFolder();
              if (v == 'rename') _renameSelected();
              if (v == 'delete') _deleteSelected();
            },
            itemBuilder: (_) => [
              _menuItem('new_folder', Icons.create_new_folder_outlined, 'New Folder'),
              _menuItem('rename', Icons.drive_file_rename_outline, 'Rename',
                  enabled: prov.selectedEntries.length == 1),
              _menuItem('delete', Icons.delete_outline, 'Delete',
                  enabled: prov.selectedEntries.isNotEmpty, isDestructive: true),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Text('Actions',
                    style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 12)),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF888888)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {bool enabled = true, bool isDestructive = false}) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(children: [
        Icon(icon,
            size: 14,
            color: isDestructive
                ? Colors.red
                : enabled
                    ? const Color(0xFFD4D4D4)
                    : const Color(0xFF444444)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: isDestructive
                    ? Colors.red
                    : enabled
                        ? const Color(0xFFD4D4D4)
                        : const Color(0xFF444444))),
      ]),
    );
  }

  Widget _buildFilterBar(LocalFilePanelProvider prov) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        autofocus: true,
        style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Filter by name…',
          hintStyle: const TextStyle(color: Color(0xFF444444), fontSize: 13),
          prefixIcon:
              const Icon(Icons.search, size: 15, color: Color(0xFF555555)),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF22C55E))),
        ),
        onChanged: prov.setFilterQuery,
      ),
    );
  }

  Widget _buildBreadcrumb(LocalFilePanelProvider prov) {
    final crumbs = _buildCrumbs(prov.currentPath);
    return Container(
      height: 34,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Back
          IconButton(
            icon: Icon(Icons.chevron_left,
                size: 16,
                color: prov.canGoBack
                    ? const Color(0xFF888888)
                    : const Color(0xFF333333)),
            onPressed: prov.canGoBack ? prov.goBack : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          // Forward
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 16,
                color: prov.canGoForward
                    ? const Color(0xFF888888)
                    : const Color(0xFF333333)),
            onPressed: prov.canGoForward ? prov.goForward : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right,
                            size: 13, color: Color(0xFF444444)),
                      ),
                    GestureDetector(
                      onTap: () => prov.loadDirectory(crumbs[i].path),
                      child: Text(
                        crumbs[i].label,
                        style: TextStyle(
                          color: i == crumbs.length - 1
                              ? const Color(0xFFD4D4D4)
                              : const Color(0xFF666666),
                          fontSize: 12,
                          fontWeight: i == crumbs.length - 1
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 13, color: Color(0xFF555555)),
            onPressed: prov.reload,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader() {
    return Container(
      height: 26,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Text('Name',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
          Expanded(
            flex: 3,
            child: Text('Date Modified',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
          SizedBox(
            width: 70,
            child: Text('Size',
                style: TextStyle(
                    color: Color(0xFF555555), fontSize: 11),
                textAlign: TextAlign.right),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text('Kind',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(LocalFilePanelProvider prov) {
    if (prov.loadState == LocalFilePanelLoadState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (prov.loadState == LocalFilePanelLoadState.error) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 28),
          const SizedBox(height: 8),
          Text(prov.errorMessage ?? 'Error',
              style:
                  const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: prov.reload,
            icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF888888)),
            label: const Text('Retry',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
          ),
        ]),
      );
    }
    final entries = prov.filteredEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          prov.filterQuery.isNotEmpty ? 'No matches' : 'Empty directory',
          style: const TextStyle(color: Color(0xFF444444), fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) => _buildEntryRow(entries[i], prov),
    );
  }

  Widget _buildEntryRow(LocalEntry entry, LocalFilePanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return Draggable<LocalEntry>(
      data: entry,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(entry.name,
              style: const TextStyle(
                  color: Color(0xFF22C55E), fontSize: 13)),
        ),
      ),
      child: GestureDetector(
        onTap: () {
          final isMulti = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isMulti) {
            prov.toggleSelection(entry);
          } else {
            prov.selectOnly(entry);
          }
        },
        onDoubleTap: () {
          if (entry.isDirectory) prov.loadDirectory(entry.path);
        },
        onSecondaryTap: () {
          prov.selectOnly(entry);
          _showContextMenu(entry, prov);
        },
        child: Container(
          color: isSelected
              ? const Color(0xFF22C55E).withValues(alpha: 0.08)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              // Name column
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Icon(
                      entry.isDirectory
                          ? Icons.folder
                          : _fileIcon(entry.extension),
                      size: 15,
                      color: entry.isDirectory
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.name,
                              style: const TextStyle(
                                  color: Color(0xFFD4D4D4), fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                          Text(entry.permissions,
                              style: const TextStyle(
                                  color: Color(0xFF444444),
                                  fontSize: 10,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Date Modified
              Expanded(
                flex: 3,
                child: Text(
                  _formatDate(entry.modifiedAt),
                  style: const TextStyle(
                      color: Color(0xFF666666), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Size
              SizedBox(
                width: 70,
                child: Text(
                  entry.formattedSize,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Kind
              SizedBox(
                width: 70,
                child: Text(
                  entry.kindLabel,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(LocalEntry entry, LocalFilePanelProvider prov) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 0, 0),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF2A2A2A))),
      items: [
        PopupMenuItem(
          onTap: _renameSelected,
          child: _contextItem(Icons.drive_file_rename_outline, 'Rename'),
        ),
        PopupMenuItem(
          onTap: _deleteSelected,
          child: _contextItem(Icons.delete_outline, 'Delete',
              color: Colors.red),
        ),
      ],
    );
  }

  Widget _contextItem(IconData icon, String label,
      {Color color = const Color(0xFFD4D4D4)}) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: color)),
    ]);
  }

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'go' || 'rs' || 'c' || 'cpp' =>
        Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}/${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ── Helpers ──────────────────────────────────────────────

  List<({String label, String path})> _buildCrumbs(String path) {
    if (Platform.isWindows) {
      final parts =
          path.split('\\').where((s) => s.isNotEmpty).toList();
      return [
        for (int i = 0; i < parts.length; i++)
          (
            label: parts[i],
            path: parts.sublist(0, i + 1).join('\\') +
                (i == 0 ? '\\' : ''),
          )
      ];
    }
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return [
      (label: 'Macintosh HD', path: '/'),
      for (int i = 0; i < parts.length; i++)
        (
          label: parts[i],
          path: '/${parts.sublist(0, i + 1).join('/')}',
        ),
    ];
  }

  static Future<String?> _showInputDialog(BuildContext context,
      {required String title,
      required String hint,
      String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title,
            style: const TextStyle(
                color: Color(0xFFD4D4D4), fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
              color: Color(0xFFD4D4D4), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: Color(0xFF555555), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF111111),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF2A2A2A))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF2A2A2A))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF22C55E))),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK',
                style: TextStyle(color: Color(0xFF22C55E))),
          ),
        ],
      ),
    );
  }
}

// ── _HeaderButton ────────────────────────────────────────────

class _HeaderButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF22C55E).withValues(alpha: 0.12)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: active
                  ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                  : const Color(0xFF2A2A2A)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? const Color(0xFF22C55E)
                : const Color(0xFFD4D4D4),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
```

- [x] **Step 2: Run analyze — expect no errors**

```bash
cd app && flutter analyze lib/widgets/local_file_panel.dart
```

Expected: No issues found.

- [x] **Step 3: Commit**

```bash
git add app/lib/widgets/local_file_panel.dart
git commit -m "feat: add LocalFilePanel widget with breadcrumb, filter, actions"
```

---

## Task 4: Update SftpPanel

**Files:**
- Modify: `app/lib/widgets/sftp_panel.dart`

Changes:
1. `host` becomes `Host?` (nullable)
2. Accept `SftpPanelProvider provider` as constructor param (externally owned)
3. Show empty state when `host == null`
4. Wrap file rows with `Draggable<SftpEntry>`

- [x] **Step 1: Replace `app/lib/widgets/sftp_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/sftp_transfer_service.dart';
import 'code_editor_screen.dart';

class SftpPanel extends StatefulWidget {
  final Host? host;
  final String panelId;
  final SftpPanelProvider provider;
  final VoidCallback onChangeHost;

  const SftpPanel({
    super.key,
    required this.host,
    required this.panelId,
    required this.provider,
    required this.onChangeHost,
  });

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.host != null) {
      _loadDirectory('/');
    }
  }

  @override
  void didUpdateWidget(SftpPanel old) {
    super.didUpdateWidget(old);
    if (old.host?.id != widget.host?.id && widget.host != null) {
      widget.provider
        ..setLoadState(SftpPanelLoadState.idle)
        ..setPath('/');
      _loadDirectory('/');
    }
  }

  Future<void> _loadDirectory(String path) async {
    final host = widget.host;
    if (host == null) return;
    widget.provider.setLoadState(SftpPanelLoadState.loading);
    widget.provider.setPath(path);
    try {
      final service = context.read<SftpTransferService>();
      final entries = await service.listDirectory(host, path);
      widget.provider.setEntries(entries);
      widget.provider.setLoadState(SftpPanelLoadState.loaded);
    } catch (e) {
      widget.provider.setLoadState(SftpPanelLoadState.error,
          error: e.toString());
    }
  }

  void _onEntryTap(SftpEntry entry) {
    if (entry.isDirectory) {
      _loadDirectory(entry.path);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CodeEditorScreen(host: widget.host!, entry: entry),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.host == null) {
      return _buildEmptyState();
    }
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<SftpPanelProvider>(
        builder: (context, prov, _) => Column(
          children: [
            _buildPathBar(prov),
            Expanded(child: _buildContent(prov)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder_outlined,
                size: 32, color: Color(0xFF444444)),
          ),
          const SizedBox(height: 16),
          const Text('Connect to host',
              style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Start by connecting to a saved host\nto manage your files with SFTP.',
            style: TextStyle(color: Color(0xFF555555), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: widget.onChangeHost,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: const Text('Select host',
                  style: TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathBar(SftpPanelProvider prov) {
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward,
                size: 14, color: Color(0xFF888888)),
            onPressed: () {
              prov.navigateUp();
              _loadDirectory(prov.currentPath);
            },
            tooltip: 'Up',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          GestureDetector(
            onTap: widget.onChangeHost,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dns, size: 11, color: Color(0xFF22C55E)),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.host!.username}@${widget.host!.host}',
                    style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.unfold_more,
                      size: 11, color: Color(0xFF555555)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              prov.currentPath,
              style: const TextStyle(
                  color: Color(0xFF888888),
                  fontFamily: 'monospace',
                  fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh,
                size: 14, color: Color(0xFF888888)),
            onPressed: () => _loadDirectory(prov.currentPath),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SftpPanelProvider prov) {
    if (prov.loadState == SftpPanelLoadState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (prov.loadState == SftpPanelLoadState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(prov.errorMessage ?? 'Error',
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (prov.entries.isEmpty) {
      return const Center(
        child: Text('Empty directory',
            style: TextStyle(color: Color(0xFF555555))),
      );
    }
    return ListView.builder(
      itemCount: prov.entries.length,
      itemBuilder: (_, i) => _buildEntryTile(prov.entries[i], prov),
    );
  }

  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return Draggable<SftpEntry>(
      data: entry,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(entry.name,
              style: const TextStyle(
                  color: Color(0xFF22C55E), fontSize: 13)),
        ),
      ),
      child: InkWell(
        onTap: () => _onEntryTap(entry),
        onSecondaryTap: () => prov.toggleSelection(entry),
        child: Container(
          color: isSelected
              ? const Color(0xFF22C55E).withValues(alpha: 0.1)
              : Colors.transparent,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                entry.isDirectory
                    ? Icons.folder
                    : _fileIcon(entry.extension),
                size: 16,
                color: entry.isDirectory
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF60A5FA),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.name,
                    style: const TextStyle(
                        color: Color(0xFFD4D4D4), fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(entry.formattedSize,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'go' ||
      'rs' ||
      'c' ||
      'cpp' =>
        Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }
}
```

- [x] **Step 2: Run analyze — expect no errors**

```bash
cd app && flutter analyze lib/widgets/sftp_panel.dart
```

Expected: No issues found.

- [x] **Step 3: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart
git commit -m "feat: update SftpPanel — nullable host, external provider, empty state, draggable rows"
```

---

## Task 5: Update SftpTransferService

**Files:**
- Modify: `app/lib/services/sftp_transfer_service.dart`

Add two new methods: `copyLocalToRemote` and `copyRemoteToLocal`. These replace the existing `copyBetweenPanels` which is no longer needed.

- [x] **Step 1: Replace `app/lib/services/sftp_transfer_service.dart`**

```dart
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import 'ssh_service.dart';

class SftpTransferService {
  final SshService _sshService;

  SftpTransferService(this._sshService);

  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    final items = await sftp.listdir(path);
    sftp.close();

    return items
        .where((item) => item.filename != '.' && item.filename != '..')
        .map((item) => SftpEntry(
              name: item.filename,
              path: p.posix.join(path, item.filename),
              isDirectory: item.attr.isDirectory,
              size: item.attr.size ?? 0,
              modifiedAt: item.attr.modifyTime != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      item.attr.modifyTime! * 1000)
                  : DateTime.now(),
            ))
        .toList();
  }

  Future<String?> downloadToTemp(Host host, SftpEntry entry) async {
    final sftp = await _sshService.openSftp(host);
    final tmpDir = await getTemporaryDirectory();
    final localPath = p.join(tmpDir.path, entry.name);
    final file = await sftp.open(entry.path);
    final bytes = await file.readBytes();
    await file.close();
    await File(localPath).writeAsBytes(bytes);
    sftp.close();
    return localPath;
  }

  Future<void> uploadFile(
      Host host, String localPath, String remotePath) async {
    final sftp = await _sshService.openSftp(host);
    final bytes = await File(localPath).readAsBytes();
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    await remoteFile.writeBytes(bytes);
    await remoteFile.close();
    sftp.close();
  }

  Future<void> copyLocalToRemote({
    required String localPath,
    required Host remoteHost,
    required String remoteDir,
  }) async {
    final fileName = p.basename(localPath);
    final remotePath = p.posix.join(remoteDir, fileName);
    await uploadFile(remoteHost, localPath, remotePath);
  }

  Future<void> copyRemoteToLocal({
    required Host remoteHost,
    required SftpEntry remoteEntry,
    required String localDir,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    final remoteFile = await sftp.open(remoteEntry.path);
    final bytes = await remoteFile.readBytes();
    await remoteFile.close();
    sftp.close();
    final localPath = p.join(localDir, remoteEntry.name);
    await File(localPath).writeAsBytes(bytes);
  }
}
```

- [x] **Step 2: Run analyze — expect no errors**

```bash
cd app && flutter analyze lib/services/sftp_transfer_service.dart
```

Expected: No issues found.

- [x] **Step 3: Commit**

```bash
git add app/lib/services/sftp_transfer_service.dart
git commit -m "feat: add copyLocalToRemote and copyRemoteToLocal to SftpTransferService"
```

---

## Task 6: Update DualPanelSftpScreen

**Files:**
- Modify: `app/lib/widgets/dual_panel_sftp_screen.dart`

This is the final wiring task. Replace the whole file with the new layout: left=`LocalFilePanel`, right=`SftpPanel`, center transfer bar with ←/→ buttons and drag-and-drop.

- [x] **Step 1: Replace `app/lib/widgets/dual_panel_sftp_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/local_entry.dart';
import '../models/sftp_entry.dart';
import '../providers/host_provider.dart';
import '../providers/local_file_panel_provider.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import 'local_file_panel.dart';
import 'sftp_panel.dart';

class DualPanelSftpScreen extends StatefulWidget {
  const DualPanelSftpScreen({super.key});

  @override
  State<DualPanelSftpScreen> createState() => _DualPanelSftpScreenState();
}

class _DualPanelSftpScreenState extends State<DualPanelSftpScreen> {
  Host? _remoteHost;
  late LocalFilePanelProvider _localProvider;
  late SftpPanelProvider _remoteProvider;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _localProvider = LocalFilePanelProvider();
    _remoteProvider = SftpPanelProvider();
  }

  @override
  void dispose() {
    _localProvider.dispose();
    _remoteProvider.dispose();
    super.dispose();
  }

  Future<void> _pickHost() async {
    final hosts = context.read<HostProvider>().allHosts;
    if (hosts.isEmpty) return;
    final picked = await showDialog<Host>(
      context: context,
      builder: (ctx) => _HostPickerDialog(hosts: hosts, current: _remoteHost),
    );
    if (picked != null && picked.id != _remoteHost?.id) {
      setState(() => _remoteHost = picked);
    }
  }

  // ── Transfer: local → remote ─────────────────────────────

  Future<void> _uploadSelected() async {
    final host = _remoteHost;
    if (host == null) return;
    final selected = _localProvider.selectedEntries.where((e) => !e.isDirectory).toList();
    if (selected.isEmpty) return;

    setState(() => _isTransferring = true);
    final service = context.read<SftpTransferService>();
    final remoteDir = _remoteProvider.currentPath;
    try {
      for (final entry in selected) {
        await service.copyLocalToRemote(
          localPath: entry.path,
          remoteHost: host,
          remoteDir: remoteDir,
        );
      }
      _remoteProvider.setLoadState(SftpPanelLoadState.loading);
      final entries = await service.listDirectory(host, remoteDir);
      _remoteProvider
        ..setEntries(entries)
        ..setLoadState(SftpPanelLoadState.loaded);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'),
              backgroundColor: const Color(0xFF2A1A1A)),
        );
      }
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  // ── Transfer: remote → local ─────────────────────────────

  Future<void> _downloadSelected() async {
    final host = _remoteHost;
    if (host == null) return;
    final selected = _remoteProvider.selectedEntries.where((e) => !e.isDirectory).toList();
    if (selected.isEmpty) return;

    setState(() => _isTransferring = true);
    final service = context.read<SftpTransferService>();
    final localDir = _localProvider.currentPath;
    try {
      for (final entry in selected) {
        await service.copyRemoteToLocal(
          remoteHost: host,
          remoteEntry: entry,
          localDir: localDir,
        );
      }
      await _localProvider.reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'),
              backgroundColor: const Color(0xFF2A1A1A)),
        );
      }
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  // ── Drag handlers ────────────────────────────────────────

  Future<void> _onLocalEntryDroppedOnRemote(LocalEntry entry) async {
    if (_remoteHost == null || entry.isDirectory) return;
    _localProvider.selectOnly(entry);
    await _uploadSelected();
  }

  Future<void> _onRemoteEntryDroppedOnLocal(SftpEntry entry) async {
    if (_remoteHost == null || entry.isDirectory) return;
    _remoteProvider.toggleSelection(entry);
    await _downloadSelected();
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (ctx) => SftpTransferService(ctx.read<SshService>()),
      child: ListenableBuilder(
        listenable: Listenable.merge([_localProvider, _remoteProvider]),
        builder: (context, _) => Column(
          children: [
            if (_isTransferring)
              const LinearProgressIndicator(
                color: Color(0xFF22C55E),
                backgroundColor: Color(0xFF1A1A1A),
                minHeight: 2,
              ),
            Expanded(
              child: Row(
                children: [
                  // Left: local panel
                  Expanded(
                    child: DragTarget<SftpEntry>(
                      onAcceptWithDetails: (d) =>
                          _onRemoteEntryDroppedOnLocal(d.data),
                      builder: (context, candidates, _) => Container(
                        decoration: BoxDecoration(
                          border: candidates.isNotEmpty
                              ? Border.all(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.4),
                                  width: 2)
                              : null,
                        ),
                        child: LocalFilePanel(provider: _localProvider),
                      ),
                    ),
                  ),
                  // Center: transfer bar
                  _buildTransferBar(),
                  // Right: remote panel
                  Expanded(
                    child: DragTarget<LocalEntry>(
                      onAcceptWithDetails: (d) =>
                          _onLocalEntryDroppedOnRemote(d.data),
                      builder: (context, candidates, _) => Container(
                        decoration: BoxDecoration(
                          border: candidates.isNotEmpty
                              ? Border.all(
                                  color: const Color(0xFF22C55E)
                                      .withValues(alpha: 0.4),
                                  width: 2)
                              : null,
                        ),
                        child: SftpPanel(
                          key: ValueKey('remote_${_remoteHost?.id}'),
                          host: _remoteHost,
                          panelId: 'remote',
                          provider: _remoteProvider,
                          onChangeHost: _pickHost,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferBar() {
    final canUpload = _remoteHost != null &&
        _localProvider.selectedEntries.any((e) => !e.isDirectory) &&
        !_isTransferring;
    final canDownload = _remoteHost != null &&
        _remoteProvider.selectedEntries.any((e) => !e.isDirectory) &&
        !_isTransferring;

    return Container(
      width: 36,
      color: const Color(0xFF111111),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Upload: local → remote
          _TransferButton(
            icon: Icons.arrow_forward,
            tooltip: 'Upload to remote',
            enabled: canUpload,
            onTap: _uploadSelected,
          ),
          const SizedBox(height: 8),
          // Download: remote → local
          _TransferButton(
            icon: Icons.arrow_back,
            tooltip: 'Download to local',
            enabled: canDownload,
            onTap: _downloadSelected,
          ),
        ],
      ),
    );
  }
}

// ── _TransferButton ──────────────────────────────────────────

class _TransferButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _TransferButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: enabled
                ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled
                  ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                  : const Color(0xFF252525),
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled
                ? const Color(0xFF22C55E)
                : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }
}

// ── _HostPickerDialog ────────────────────────────────────────

class _HostPickerDialog extends StatelessWidget {
  final List<Host> hosts;
  final Host? current;

  const _HostPickerDialog({required this.hosts, required this.current});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: Color(0xFF2A2A2A)))),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined,
                      size: 15, color: Color(0xFF888888)),
                  const SizedBox(width: 8),
                  const Text('Select Remote Host',
                      style: TextStyle(
                          color: Color(0xFFD4D4D4),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close,
                        size: 14, color: Color(0xFF555555)),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: hosts.length,
                itemBuilder: (_, i) {
                  final h = hosts[i];
                  final isActive = h.id == current?.id;
                  return InkWell(
                    onTap: () => Navigator.pop(context, h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: isActive
                          ? const Color(0xFF22C55E)
                              .withValues(alpha: 0.08)
                          : Colors.transparent,
                      child: Row(children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.dns,
                              size: 14,
                              color: Color(0xFF22C55E)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(h.label,
                                  style: TextStyle(
                                    color: isActive
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFD4D4D4),
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  )),
                              Text(
                                '${h.username}@${h.host}:${h.port}',
                                style: const TextStyle(
                                    color: Color(0xFF555555),
                                    fontSize: 11,
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        if (isActive)
                          const Icon(Icons.check,
                              size: 14,
                              color: Color(0xFF22C55E)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 2: Run analyze — expect no errors**

```bash
cd app && flutter analyze lib/widgets/dual_panel_sftp_screen.dart
```

Expected: No issues found.

- [x] **Step 3: Run the app and verify manually**

```bash
cd app && flutter run -d macos
```

Manual checklist:
- [x] Navigate to SFTP tab — left panel shows local files from home directory
- [x] Breadcrumb shows "Macintosh HD > Users > ..." with clickable segments
- [x] Back/forward arrows work after navigating into folders
- [x] Double-click a folder navigates into it
- [x] Filter button shows search field; typing filters the list
- [x] Actions > New Folder creates a folder in the current directory
- [x] Select a file, Actions > Delete shows confirmation and deletes
- [x] Select a single file, Actions > Rename shows dialog and renames
- [x] Right panel shows "Connect to host" empty state with "Select host" button
- [x] Clicking "Select host" opens the host picker
- [x] After selecting a host, right panel loads remote directory
- [x] Select a local file → click → button → file appears in remote panel
- [x] Select a remote file → click ← button → file appears in local panel
- [x] Drag a local file onto the right panel → triggers upload
- [x] Drag a remote file onto the left panel → triggers download

- [x] **Step 4: Commit**

```bash
git add app/lib/widgets/dual_panel_sftp_screen.dart
git commit -m "feat: wire DualPanelSftpScreen — local left, remote right, transfer bar, drag-and-drop"
```

---

## Self-Review Notes

- Spec §LocalEntry fields: all covered in Task 1
- Spec §LocalFilePanelProvider history: covered in Task 2 (`pushPath`, `goBack`, `goForward`)
- Spec §LocalFilePanel Filter: covered in Task 3 (`_buildFilterBar`)
- Spec §LocalFilePanel Actions (New Folder, Rename, Delete): covered in Task 3
- Spec §Breadcrumb clickable: covered in Task 3 (`_buildCrumbs` + `GestureDetector`)
- Spec §SftpPanel empty state: covered in Task 4 (`_buildEmptyState`)
- Spec §Draggable rows: covered in Tasks 3 and 4
- Spec §Transfer bar ←/→: covered in Task 6
- Spec §Drag-and-drop DragTarget: covered in Task 6
- Spec §copyLocalToRemote / copyRemoteToLocal: covered in Task 5
- Spec §Error handling (SnackBar for transfers, inline for local I/O): covered in Tasks 3 and 6
- Type consistency: `LocalEntry` used consistently across Tasks 1, 2, 3, 6; `SftpPanelProvider` passed externally in Tasks 4 and 6; `SftpTransferService` method names match between Tasks 5 and 6
