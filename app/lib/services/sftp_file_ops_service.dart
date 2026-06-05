import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import '../models/host.dart';
import 'ssh_service.dart';

/// Child entry shape consumed by the recursive walks (chmod, delete).
typedef WalkChild = ({String name, bool isDirectory, bool isSymlink});

class SftpFileOpsService {
  final SshService _sshService;

  SftpFileOpsService(this._sshService);

  Future<void> rename(Host host, String oldPath, String newPath) async {
    final sftp = await _sshService.openSftp(host);
    try {
      await sftp.rename(oldPath, newPath);
    } finally {
      sftp.close();
    }
  }

  Future<void> mkdir(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      await sftp.mkdir(path);
    } finally {
      sftp.close();
    }
  }

  Future<void> createFile(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await file.close();
    } finally {
      sftp.close();
    }
  }

  Future<void> delete(Host host, String path, {required bool isDirectory}) async {
    final sftp = await _sshService.openSftp(host);
    try {
      if (isDirectory) {
        await _deleteRecursive(sftp, path);
      } else {
        await sftp.remove(path);
      }
    } finally {
      sftp.close();
    }
  }

  /// The full st_mode value for [path] via stat(), or null when the server
  /// doesn't report one. Fallback for listings that omitted the permissions
  /// attribute (legal in SFTP v3) so the chmod dialog never opens at 000.
  Future<int?> statMode(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      return (await sftp.stat(path)).mode?.value;
    } finally {
      sftp.close();
    }
  }

  /// Sets permission bits [mode] (e.g. 0x1ED for 0o755) on [path].
  /// With [recursive] and [isDirectory], applies the same bits to every
  /// child, like `chmod -R`.
  Future<void> chmod(Host host, String path, int mode,
      {bool isDirectory = false, bool recursive = false}) async {
    final sftp = await _sshService.openSftp(host);
    try {
      await chmodWalk(
        path: path,
        isDirectory: isDirectory,
        recursive: recursive,
        setMode: (entryPath) => sftp.setStat(
            entryPath, SftpFileAttrs(mode: SftpFileMode.value(mode))),
        list: (dirPath) => listWalkChildren(sftp, dirPath),
      );
    } finally {
      sftp.close();
    }
  }

  /// Lists [dirPath] with one classification policy shared by the recursive
  /// walks (chmod, delete): `.`/`..` are dropped; symlinks are reported as
  /// symlinks and never followed; entries whose listing omitted the mode
  /// attribute (legal in SFTP v3) are classified via lstat instead of
  /// silently defaulting to "file" — that default made recursive operations
  /// skip whole subtrees on servers that omit permissions.
  static Future<List<WalkChild>> listWalkChildren(
      SftpClient sftp, String dirPath) async {
    final out = <WalkChild>[];
    for (final item in await sftp.listdir(dirPath)) {
      if (item.filename == '.' || item.filename == '..') continue;
      var type = item.attr.mode?.type;
      if (type == null) {
        try {
          type = (await sftp.stat(p.posix.join(dirPath, item.filename),
                  followLink: false))
              .mode
              ?.type;
        } catch (_) {
          // Unclassifiable — falls through as a leaf.
        }
      }
      out.add((
        name: item.filename,
        isDirectory: type == SftpFileType.directory,
        isSymlink: type == SftpFileType.symbolicLink,
      ));
    }
    return out;
  }

  /// File children within one directory are chmodded concurrently in
  /// batches of this size; directories recurse sequentially so the number
  /// of in-flight SFTP requests stays bounded.
  static const _chmodBatch = 8;

  /// Recursion driver for [chmod], callback-injected for tests (same
  /// pattern as [SftpTransferService.pipeChunks]).
  ///
  /// Policy:
  /// - symlink children are skipped entirely — SFTP v3 SETSTAT follows the
  ///   link, so chmod-ing one would alter the target (possibly outside the
  ///   tree); `chmod -R` skips traversal symlinks for the same reason;
  /// - a directory's own mode is applied *after* its subtree (post-order):
  ///   a restrictive target mode like 600 must not strip our own r/x while
  ///   the walk is still inside.
  static Future<void> chmodWalk({
    required String path,
    required bool isDirectory,
    required bool recursive,
    required Future<void> Function(String path) setMode,
    required Future<List<WalkChild>> Function(String path) list,
  }) async {
    if (!recursive || !isDirectory) {
      await setMode(path);
      return;
    }
    final files = <String>[];
    for (final child in await list(path)) {
      if (child.name == '.' || child.name == '..') continue;
      if (child.isSymlink) continue;
      if (child.isDirectory) {
        await chmodWalk(
          path: p.posix.join(path, child.name),
          isDirectory: true,
          recursive: true,
          setMode: setMode,
          list: list,
        );
      } else {
        files.add(p.posix.join(path, child.name));
      }
    }
    for (var i = 0; i < files.length; i += _chmodBatch) {
      await Future.wait(files.skip(i).take(_chmodBatch).map(setMode));
    }
    await setMode(path);
  }

  Future<void> _deleteRecursive(SftpClient sftp, String path) async {
    // Same classification policy as chmodWalk: a symlink child is removed
    // as the link itself (never followed into), and entries with omitted
    // modes are classified via lstat instead of being mis-handled as files.
    for (final child in await listWalkChildren(sftp, path)) {
      final childPath = p.posix.join(path, child.name);
      if (child.isDirectory) {
        await _deleteRecursive(sftp, childPath);
      } else {
        await sftp.remove(childPath);
      }
    }
    await sftp.rmdir(path);
  }
}
