import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';

// POSIX file-type bits (upper bits of st_mode).
const _kRegular = 0x8000;
const _kDirectory = 0x4000;
const _kSymlink = 0xA000;

SftpFileAttrs _attrs(int typeBits, {int? size}) =>
    SftpFileAttrs(mode: SftpFileMode.value(typeBits), size: size);

void main() {
  group('pipeChunks', () {
    test('reads to EOF when stat size is zero (procfs-style files)', () async {
      // /proc files stat as size 0 but still have content.
      final reads = <(int, int)>[];
      final out = <int>[];
      await SftpTransferService.pipeChunks(
        statSize: 0,
        read: (length, offset) async {
          reads.add((length, offset));
          if (offset == 0) return Uint8List.fromList(List.filled(5, 1));
          return Uint8List(0); // EOF
        },
        add: out.addAll,
      );
      expect(out.length, 5, reason: 'content past stat size must be read');
    });

    test('bounded phase requests exactly the remaining stat size', () async {
      // Servers that answer past-EOF reads with SSH_FX_FAILURE must never
      // see a read request beyond the stat'd size while within it.
      const chunk = 64 * 1024;
      const size = chunk + 100;
      final reads = <(int, int)>[];
      final out = <int>[];
      await SftpTransferService.pipeChunks(
        statSize: size,
        read: (length, offset) async {
          reads.add((length, offset));
          if (offset >= size) return Uint8List(0); // EOF
          return Uint8List(length);
        },
        add: out.addAll,
      );
      expect(out.length, size);
      expect(reads[0], (chunk, 0));
      expect(reads[1], (100, chunk), reason: 'second request must be bounded');
    });

    test('treats past-EOF SSH_FX_FAILURE as EOF once stat size is read',
        () async {
      final out = <int>[];
      await SftpTransferService.pipeChunks(
        statSize: 5,
        read: (length, offset) async {
          if (offset >= 5) {
            throw SftpStatusError(SftpStatusCode.failure, 'Failure');
          }
          return Uint8List.fromList(List.filled(5, 1));
        },
        add: out.addAll,
      );
      expect(out.length, 5);
    });

    test('keeps reading past stat size when the file grew', () async {
      final out = <int>[];
      await SftpTransferService.pipeChunks(
        statSize: 5,
        read: (length, offset) async {
          if (offset == 0) return Uint8List.fromList(List.filled(5, 1));
          if (offset == 5) return Uint8List.fromList(List.filled(3, 2));
          return Uint8List(0); // EOF
        },
        add: out.addAll,
      );
      expect(out.length, 8, reason: 'bytes appended after stat must be read');
    });

    test('rethrows non-failure status errors', () async {
      expect(
        () => SftpTransferService.pipeChunks(
          statSize: 0,
          read: (length, offset) async {
            throw SftpStatusError(
                SftpStatusCode.permissionDenied, 'Permission denied');
          },
          add: (_) {},
        ),
        throwsA(isA<SftpStatusError>()),
      );
    });

    test('rethrows failure raised before the stat size is consumed', () async {
      // A FAILURE mid-file (within the stat'd size) is a real error, not the
      // past-EOF quirk.
      expect(
        () => SftpTransferService.pipeChunks(
          statSize: 10,
          read: (length, offset) async {
            throw SftpStatusError(SftpStatusCode.failure, 'Failure');
          },
          add: (_) {},
        ),
        throwsA(isA<SftpStatusError>()),
      );
    });

    test('stops when the file shrank mid-transfer', () async {
      final reads = <int>[];
      final out = <int>[];
      await SftpTransferService.pipeChunks(
        statSize: 10,
        read: (length, offset) async {
          reads.add(offset);
          return Uint8List(0); // EOF before the stat'd size
        },
        add: out.addAll,
      );
      expect(out, isEmpty);
      expect(reads, [0], reason: 'no further reads after early EOF');
    });

    test('reports running offset after each chunk', () async {
      final offsets = <int>[];
      await SftpTransferService.pipeChunks(
        statSize: 5,
        read: (length, offset) async {
          if (offset == 0) return Uint8List.fromList(List.filled(5, 1));
          return Uint8List(0);
        },
        add: (_) {},
        onProgress: offsets.add,
      );
      expect(offsets, [5]);
    });
  });

  group('resolveEntryIsDirectory', () {
    test('plain directory is a directory without statting', () async {
      var statted = false;
      final isDir = await SftpTransferService.resolveEntryIsDirectory(
        attr: _attrs(_kDirectory),
        path: '/srv/www',
        stat: (_) async {
          statted = true;
          return _attrs(_kDirectory);
        },
      );
      expect(isDir, isTrue);
      expect(statted, isFalse);
    });

    test('plain file is not a directory', () async {
      final isDir = await SftpTransferService.resolveEntryIsDirectory(
        attr: _attrs(_kRegular),
        path: '/srv/file',
        stat: (_) async => _attrs(_kRegular),
      );
      expect(isDir, isFalse);
    });

    test('symlink to a directory resolves as directory', () async {
      final isDir = await SftpTransferService.resolveEntryIsDirectory(
        attr: _attrs(_kSymlink),
        path: '/bin',
        stat: (path) async {
          expect(path, '/bin');
          return _attrs(_kDirectory);
        },
      );
      expect(isDir, isTrue);
    });

    test('symlink to a file resolves as file', () async {
      final isDir = await SftpTransferService.resolveEntryIsDirectory(
        attr: _attrs(_kSymlink),
        path: '/etc/motd',
        stat: (_) async => _attrs(_kRegular),
      );
      expect(isDir, isFalse);
    });

    test('dangling symlink keeps file semantics', () async {
      final isDir = await SftpTransferService.resolveEntryIsDirectory(
        attr: _attrs(_kSymlink),
        path: '/broken',
        stat: (_) async =>
            throw SftpStatusError(SftpStatusCode.noSuchFile, 'No such file'),
      );
      expect(isDir, isFalse);
    });
  });
}
