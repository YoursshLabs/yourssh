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
}
