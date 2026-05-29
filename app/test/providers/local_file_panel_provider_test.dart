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
