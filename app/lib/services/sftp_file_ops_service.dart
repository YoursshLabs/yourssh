import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import '../models/host.dart';
import 'ssh_service.dart';

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
        list: (dirPath) async => [
          for (final item in await sftp.listdir(dirPath))
            (name: item.filename, isDirectory: item.attr.isDirectory),
        ],
      );
    } finally {
      sftp.close();
    }
  }

  /// Recursion driver for [chmod], callback-injected for tests (same
  /// pattern as [SftpTransferService.pipeChunks]).
  static Future<void> chmodWalk({
    required String path,
    required bool isDirectory,
    required bool recursive,
    required Future<void> Function(String path) setMode,
    required Future<List<({String name, bool isDirectory})>> Function(
            String path)
        list,
  }) async {
    await setMode(path);
    if (!recursive || !isDirectory) return;
    for (final child in await list(path)) {
      if (child.name == '.' || child.name == '..') continue;
      await chmodWalk(
        path: p.posix.join(path, child.name),
        isDirectory: child.isDirectory,
        recursive: true,
        setMode: setMode,
        list: list,
      );
    }
  }

  Future<void> _deleteRecursive(SftpClient sftp, String path) async {
    final items = await sftp.listdir(path);
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final child = p.posix.join(path, item.filename);
      if (item.attr.isDirectory) {
        await _deleteRecursive(sftp, child);
      } else {
        await sftp.remove(child);
      }
    }
    await sftp.rmdir(path);
  }
}
