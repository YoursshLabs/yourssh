import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies local files/directories between two local panel directories
/// (the Local → Local case of the two-panel transfer matrix).
class LocalCopyService {
  /// Copies the file or directory at [srcPath] into the directory [dstDir].
  /// Reports copied file sizes through [onBytes]. Throws [ArgumentError]
  /// when the copy would land on itself (same parent directory, or a
  /// directory copied into itself/its own subtree) and when a single-file
  /// copy would overwrite an existing destination file.
  ///
  /// Directory copies merge into an existing same-named directory but never
  /// overwrite existing files — they are skipped and reported via
  /// [onSkipped], matching the SFTP recursive transfers.
  Future<void> copyEntry(
    String srcPath,
    String dstDir, {
    void Function(int bytes)? onBytes,
    void Function(String path)? onSkipped,
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
      await _copyDirectory(
          Directory(src), p.join(dst, p.basename(src)), onBytes, onSkipped);
    } else {
      final target = p.join(dst, p.basename(src));
      if (await File(target).exists()) {
        throw ArgumentError(
            "'${p.basename(src)}' already exists in the destination");
      }
      await _copyFile(File(src), target, onBytes);
    }
  }

  Future<void> _copyDirectory(
    Directory src,
    String dstPath,
    void Function(int)? onBytes,
    void Function(String)? onSkipped,
  ) async {
    await Directory(dstPath).create(recursive: true);
    await for (final entity in src.list()) {
      final target = p.join(dstPath, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, target, onBytes, onSkipped);
      } else if (entity is File) {
        if (await File(target).exists()) {
          // Never clobber inside a merge — same contract as the SFTP
          // recursive transfers (skip + report).
          onSkipped?.call(target);
          continue;
        }
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
