import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies local files/directories between two local panel directories
/// (the Local → Local case of the two-panel transfer matrix).
class LocalCopyService {
  /// Copies the file or directory at [srcPath] into the directory [dstDir].
  /// Reports copied file sizes through [onBytes]. Throws [ArgumentError]
  /// when the copy would land on itself (same parent directory, or a
  /// directory copied into itself/its own subtree).
  Future<void> copyEntry(
    String srcPath,
    String dstDir, {
    void Function(int bytes)? onBytes,
  }) async {
    final src = p.normalize(srcPath);
    final dst = p.normalize(dstDir);

    if (p.equals(p.dirname(src), dst)) {
      throw ArgumentError('Source and destination directories are the same');
    }
    if (p.equals(src, dst) || p.isWithin(src, dst)) {
      throw ArgumentError('Cannot copy a directory into itself');
    }

    if (await FileSystemEntity.isDirectory(src)) {
      await _copyDirectory(Directory(src), p.join(dst, p.basename(src)), onBytes);
    } else {
      await _copyFile(File(src), p.join(dst, p.basename(src)), onBytes);
    }
  }

  Future<void> _copyDirectory(
    Directory src,
    String dstPath,
    void Function(int)? onBytes,
  ) async {
    await Directory(dstPath).create(recursive: true);
    await for (final entity in src.list()) {
      final target = p.join(dstPath, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, target, onBytes);
      } else if (entity is File) {
        await _copyFile(entity, target, onBytes);
      }
      // Symlinks and other entity types are skipped.
    }
  }

  Future<void> _copyFile(File src, String dstPath, void Function(int)? onBytes) async {
    await src.copy(dstPath);
    onBytes?.call(await src.length());
  }
}
