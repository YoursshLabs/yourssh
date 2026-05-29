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
    test('returns extension string for any non-empty extension', () {
      final e = LocalEntry(
          name: 'foo.xyz', path: '/foo.xyz', isDirectory: false, size: 0,
          modifiedAt: DateTime(2024), permissions: '-rw-r--r--');
      expect(e.kindLabel, 'xyz');
    });
  });
}
