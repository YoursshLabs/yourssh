import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/util/safe_local_path.dart';

// POSIX file-type bits (upper bits of st_mode).
const _kRegular = 0x8000;
const _kDirectory = 0x4000;
const _kSymlink = 0xA000;

SftpFileAttrs _attrs(int typeBits, {int? size}) =>
    SftpFileAttrs(mode: SftpFileMode.value(typeBits), size: size);

void main() {
  pathTraversalTests();
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

// ---------------------------------------------------------------------------
// Path-traversal hardening (server-controlled names)
// ---------------------------------------------------------------------------

class _FakeSshService implements SshService {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('SSH must not be touched: ${i.memberName}');
}

class _FakeFile implements SftpFile {
  _FakeFile(this.content);
  final List<int> content;
  @override
  Future<SftpFileAttrs> stat() async =>
      SftpFileAttrs(size: content.length, mode: SftpFileMode.value(_kRegular));
  @override
  Future<Uint8List> readBytes({int? length, int offset = 0}) async {
    if (offset >= content.length) return Uint8List(0);
    final end = length == null
        ? content.length
        : (offset + length).clamp(0, content.length);
    return Uint8List.fromList(content.sublist(offset, end));
  }

  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// tree: remote dir path -> entries (name, attrs).
class _FakeSftp implements SftpClient {
  _FakeSftp(this.tree);
  final Map<String, List<SftpName>> tree;
  final listed = <String>[];

  @override
  Future<List<SftpName>> listdir(String path) async {
    listed.add(path);
    return tree[path] ?? const [];
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async =>
      SftpFileAttrs(mode: SftpFileMode.value(_kDirectory));

  @override
  Future<SftpFile> open(String filename,
          {SftpFileOpenMode mode = SftpFileOpenMode.read}) async =>
      _FakeFile([1, 2, 3]);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

SftpName _name(String n, int typeBits) => SftpName(
    filename: n,
    longname: n,
    attr: SftpFileAttrs(mode: SftpFileMode.value(typeBits), size: 3));

List<String> _allFiles(Directory d) => [
      for (final e in d.listSync(recursive: true, followLinks: false))
        if (e is File) e.path,
    ];

Host _host() => Host(label: 'h', host: 'h', username: 'u');

void pathTraversalTests() {
  group('path traversal hardening', () {
    late Directory sandbox;
    late Directory dest;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('sftp_trav_');
      dest = Directory(p.join(sandbox.path, 'dest'))..createSync();
    });
    tearDown(() => sandbox.deleteSync(recursive: true));

    test('directory download skips unsafe names and writes outside nothing',
        () async {
      final sftp = _FakeSftp({
        '/r/dir': [
          _name('good.txt', _kRegular),
          _name('../../escape.txt', _kRegular),
          _name('/abs_escape.txt', _kRegular),
          _name('a/..', _kRegular),
          _name('..\\x', _kRegular),
          _name('nul\u0000.txt', _kRegular),
        ],
      });
      final skipped = <String>[];
      await SftpTransferService.downloadDirTree(
        sftp: sftp,
        remotePath: '/r/dir',
        localDir: dest.path,
        onProgress: (_, _, _) {},
        onFileSkipped: skipped.add,
        isCancelled: () => false,
      );
      expect(_allFiles(dest).map(p.basename), ['good.txt']);
      // Nothing created anywhere in the sandbox other than dest/dir/good.txt.
      expect(_allFiles(sandbox), [p.join(dest.path, 'dir', 'good.txt')]);
      expect(skipped.length, 5);
    });

    test('destination dir derived from a `..` remote path is refused',
        () async {
      final sftp = _FakeSftp({'/r/x/..': [_name('f.txt', _kRegular)]});
      await expectLater(
        SftpTransferService.downloadDirTree(
          sftp: sftp,
          remotePath: '/r/x/..',
          localDir: dest.path,
          onProgress: (_, _, _) {},
          onFileSkipped: (_) {},
          isCancelled: () => false,
        ),
        throwsA(isA<UnsafeRemotePathException>()),
      );
      expect(_allFiles(sandbox), isEmpty);
    });

    test('recursion depth is capped (symlink loop) and reported as skipped',
        () async {
      // loop -> .. : every level lists one directory entry named "loop".
      final sftp = _FakeSftp({});
      var path = '/r';
      for (var i = 0; i < 200; i++) {
        sftp.tree[path] = [_name('loop', _kDirectory)];
        path = '$path/loop';
      }
      final skipped = <String>[];
      await SftpTransferService.downloadDirTree(
        sftp: sftp,
        remotePath: '/r',
        localDir: dest.path,
        onProgress: (_, _, _) {},
        onFileSkipped: skipped.add,
        isCancelled: () => false,
      );
      expect(sftp.listed.length, lessThanOrEqualTo(65));
      expect(skipped, isNotEmpty);
    });

    test('downloadToTemp rejects an unsafe name before touching SSH', () async {
      final svc = SftpTransferService(_FakeSshService());
      final entry = SftpEntry(
          name: '../../.zshrc',
          path: '/r/x',
          isDirectory: false,
          size: 0,
          modifiedAt: DateTime(2020));
      await expectLater(svc.downloadToTemp(_host(), entry),
          throwsA(isA<UnsafeRemotePathException>()));
    });

    test('copyRemoteToLocal rejects an unsafe name before touching SSH',
        () async {
      final svc = SftpTransferService(_FakeSshService());
      final entry = SftpEntry(
          name: '/Users/victim/.ssh/authorized_keys',
          path: '/r/x',
          isDirectory: false,
          size: 0,
          modifiedAt: DateTime(2020));
      await expectLater(
          svc.copyRemoteToLocal(
              remoteHost: _host(), remoteEntry: entry, localDir: dest.path),
          throwsA(isA<UnsafeRemotePathException>()));
      expect(_allFiles(sandbox), isEmpty);
    });
  });
}
