// app/test/models/sftp_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/sftp_entry.dart';

void main() {
  group('SftpEntry', () {
    test('isDirectory returns true for directory type', () {
      final entry = SftpEntry(name: 'mydir', path: '/home/user/mydir', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      expect(entry.isDirectory, true);
    });

    test('extension returns file extension for files', () {
      final entry = SftpEntry(name: 'main.dart', path: '/home/user/main.dart', isDirectory: false, size: 1024, modifiedAt: DateTime(2024));
      expect(entry.extension, 'dart');
    });

    test('extension returns empty string for directories', () {
      final entry = SftpEntry(name: 'src', path: '/home/user/src', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      expect(entry.extension, '');
    });

    test('formattedSize returns human-readable string', () {
      final small = SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 512, modifiedAt: DateTime(2024));
      final large = SftpEntry(name: 'b.bin', path: '/b.bin', isDirectory: false, size: 2097152, modifiedAt: DateTime(2024));
      expect(small.formattedSize, '512 B');
      expect(large.formattedSize, '2.0 MB');
    });

    test('sortKey puts directories before files', () {
      final dir = SftpEntry(name: 'src', path: '/src', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      final file = SftpEntry(name: 'main.dart', path: '/main.dart', isDirectory: false, size: 100, modifiedAt: DateTime(2024));
      expect(dir.sortKey.compareTo(file.sortKey), lessThan(0));
    });

    test('kindLabel returns "folder" for directories', () {
      final entry = SftpEntry(name: 'src', path: '/src', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      expect(entry.kindLabel, 'folder');
    });

    test('kindLabel returns "document" for files without extension', () {
      final entry = SftpEntry(name: 'Makefile', path: '/Makefile', isDirectory: false, size: 100, modifiedAt: DateTime(2024));
      expect(entry.kindLabel, 'document');
    });

    test('kindLabel returns lowercase extension for files with extension', () {
      final entry = SftpEntry(name: 'main.DART', path: '/main.DART', isDirectory: false, size: 100, modifiedAt: DateTime(2024));
      expect(entry.kindLabel, 'dart');
    });
  });
}
