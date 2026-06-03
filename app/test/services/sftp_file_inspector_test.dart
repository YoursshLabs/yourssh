// app/test/services/sftp_file_inspector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/services/sftp_file_inspector.dart';

SftpEntry _entry(String name, {int size = 10}) => SftpEntry(
      name: name,
      path: '/tmp/$name',
      isDirectory: false,
      size: size,
      modifiedAt: DateTime(2026),
    );

void main() {
  group('editBlockReason', () {
    test('plain text file is editable', () {
      expect(editBlockReason(_entry('notes.txt')), EditBlockReason.none);
    });

    test('binary extension is blocked', () {
      expect(editBlockReason(_entry('photo.png')),
          EditBlockReason.binaryExtension);
      expect(editBlockReason(_entry('archive.tar.gz')),
          EditBlockReason.binaryExtension);
      expect(editBlockReason(_entry('app.exe')),
          EditBlockReason.binaryExtension);
    });

    test('file over 5 MB is blocked', () {
      expect(editBlockReason(_entry('big.log', size: 5 * 1024 * 1024 + 1)),
          EditBlockReason.tooLarge);
    });

    test('file at exactly 5 MB is editable', () {
      expect(editBlockReason(_entry('ok.log', size: 5 * 1024 * 1024)),
          EditBlockReason.none);
    });

    test('file without extension is editable', () {
      expect(editBlockReason(_entry('Makefile')), EditBlockReason.none);
    });
  });

  group('looksBinary', () {
    test('plain ascii is not binary', () {
      expect(looksBinary('hello world\n'.codeUnits), isFalse);
    });

    test('null byte marks binary', () {
      expect(looksBinary(const [0x68, 0x00, 0x69]), isTrue);
    });

    test('null byte beyond the first 8 KB is ignored', () {
      final bytes = List<int>.filled(8193, 0x61)..[8192] = 0;
      expect(looksBinary(bytes), isFalse);
    });

    test('empty content is not binary', () {
      expect(looksBinary(const []), isFalse);
    });
  });
}
