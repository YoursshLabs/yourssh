// app/test/providers/sftp_panel_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/sftp_panel_provider.dart';
import 'package:yourssh/models/sftp_entry.dart';

void main() {
  test('initial path is /', () {
    final p = SftpPanelProvider();
    expect(p.currentPath, '/');
  });

  test('setPath updates current path and clears selection', () {
    final p = SftpPanelProvider();
    p.toggleSelection(SftpEntry(name: 'a', path: '/a', isDirectory: false, size: 0, modifiedAt: DateTime(2024)));
    p.setPath('/home/user');
    expect(p.currentPath, '/home/user');
    expect(p.selectedEntries, isEmpty);
  });

  test('toggleSelection adds and removes entries', () {
    final p = SftpPanelProvider();
    final e = SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024));
    p.toggleSelection(e);
    expect(p.selectedEntries, contains(e));
    p.toggleSelection(e);
    expect(p.selectedEntries, isEmpty);
  });

  test('clearSelection empties selection', () {
    final p = SftpPanelProvider();
    final e = SftpEntry(name: 'b.txt', path: '/b.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024));
    p.toggleSelection(e);
    p.clearSelection();
    expect(p.selectedEntries, isEmpty);
  });

  test('navigateUp moves to parent path', () {
    final p = SftpPanelProvider();
    p.setPath('/home/user/projects');
    p.navigateUp();
    expect(p.currentPath, '/home/user');
  });

  test('navigateUp at root stays at root', () {
    final p = SftpPanelProvider();
    p.navigateUp();
    expect(p.currentPath, '/');
  });

  test('selectAll selects all entries', () {
    final p = SftpPanelProvider();
    p.setEntries([
      SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024)),
      SftpEntry(name: 'b.txt', path: '/b.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024)),
    ]);
    p.selectAll();
    expect(p.selectedEntries.length, 2);
  });

  test('deselectAll clears selection', () {
    final p = SftpPanelProvider();
    final e = SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024));
    p.setEntries([e]);
    p.selectAll();
    p.deselectAll();
    expect(p.selectedEntries, isEmpty);
  });

  test('isAllSelected is true when all entries are selected', () {
    final p = SftpPanelProvider();
    p.setEntries([SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024))]);
    expect(p.isAllSelected, false);
    p.selectAll();
    expect(p.isAllSelected, true);
  });

  group('filter', () {
    SftpEntry entry(String name) => SftpEntry(
        name: name,
        path: '/$name',
        isDirectory: false,
        size: 0,
        modifiedAt: DateTime(2024));

    test('filteredEntries returns all entries when query empty', () {
      final p = SftpPanelProvider();
      p.setEntries([entry('alpha.txt'), entry('beta.log')]);
      expect(p.filteredEntries.length, 2);
    });

    test('filteredEntries matches case-insensitively by name', () {
      final p = SftpPanelProvider();
      p.setEntries([entry('Alpha.txt'), entry('beta.log')]);
      p.setFilterQuery('ALPHA');
      expect(p.filteredEntries.map((e) => e.name), ['Alpha.txt']);
    });

    test('selectAll with an active filter selects only visible entries', () {
      final p = SftpPanelProvider();
      p.setEntries([entry('a.txt'), entry('b.txt'), entry('secret.key')]);
      p.setFilterQuery('txt');
      p.selectAll();
      expect(p.selectedEntries.map((e) => e.name),
          unorderedEquals(['a.txt', 'b.txt']),
          reason: 'entries hidden by the filter must never be selected — '
              'a later Delete would remove files the user never saw');
    });

    test('isAllSelected is true when every *visible* entry is selected', () {
      final p = SftpPanelProvider();
      p.setEntries([entry('a.txt'), entry('b.txt'), entry('secret.key')]);
      p.setFilterQuery('txt');
      p.selectAll();
      expect(p.isAllSelected, isTrue);
    });

    test('narrowing the filter prunes selected entries that became hidden',
        () {
      final p = SftpPanelProvider();
      p.setEntries([entry('a.txt'), entry('secret.key')]);
      p.selectAll(); // both selected, no filter
      p.setFilterQuery('txt'); // secret.key now hidden
      expect(p.selectedEntries.map((e) => e.name), ['a.txt'],
          reason: 'select-then-filter must not keep hidden files selected');
    });

    test('toggleFilterVisible clears the query when hiding', () {
      final p = SftpPanelProvider();
      p.setEntries([entry('a'), entry('b')]);
      p.toggleFilterVisible(); // show
      p.setFilterQuery('a');
      p.toggleFilterVisible(); // hide → query reset
      expect(p.filterVisible, isFalse);
      expect(p.filteredEntries.length, 2);
    });
  });
}
