// app/lib/services/sftp_transfer_service.dart
import 'dart:io';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import 'ssh_service.dart';

class SftpTransferService {
  final SshService _sshService;

  SftpTransferService(this._sshService);

  static const _chunkSize = 64 * 1024;

  /// Core download loop, decoupled from dartssh2 for testing.
  ///
  /// Two phases:
  /// 1. While within the stat'd size, request exactly the remaining bytes so
  ///    servers that answer past-EOF reads with SSH_FX_FAILURE instead of
  ///    SSH_FX_EOF never see one (they made every download end with a
  ///    spurious error).
  /// 2. Then keep reading until EOF: covers files whose stat size is
  ///    0/unknown (procfs, pipes) and files that grew past the stat'd size.
  ///    A FAILURE answered here is the past-EOF quirk — treat it as EOF.
  @visibleForTesting
  static Future<void> pipeChunks({
    required int? statSize,
    required Future<Uint8List> Function(int length, int offset) read,
    required void Function(List<int> chunk) add,
    void Function(int offset)? onProgress,
  }) async {
    final size = statSize ?? 0;
    int offset = 0;
    while (offset < size) {
      final chunk = await read(min(_chunkSize, size - offset), offset);
      if (chunk.isEmpty) return; // file shrank mid-transfer
      add(chunk);
      offset += chunk.length;
      onProgress?.call(offset);
    }
    while (true) {
      Uint8List chunk;
      try {
        chunk = await read(_chunkSize, offset);
      } on SftpStatusError catch (e) {
        if (e.code == SftpStatusCode.failure) return; // past-EOF quirk
        rethrow;
      }
      if (chunk.isEmpty) return;
      add(chunk);
      offset += chunk.length;
      onProgress?.call(offset);
    }
  }

  /// listdir attrs have lstat semantics, so a symlink to a directory looks
  /// like a plain file (e.g. /bin -> usr/bin on merged-usr distros). Follow
  /// the link via [stat] to get the target's real type; broken links keep
  /// file semantics.
  @visibleForTesting
  static Future<bool> resolveEntryIsDirectory({
    required SftpFileAttrs attr,
    required String path,
    required Future<SftpFileAttrs> Function(String path) stat,
  }) async {
    if (attr.mode?.type != SftpFileType.symbolicLink) {
      return attr.isDirectory;
    }
    try {
      return (await stat(path)).isDirectory;
    } on SftpError {
      return false; // dangling link
    }
  }

  /// Streams [file] into [sink] in [_chunkSize] blocks. [onProgress] receives
  /// the running byte offset after each chunk (used to report transfer state).
  static Future<void> _pipeToSink(
    SftpFile file,
    IOSink sink, {
    void Function(int offset)? onProgress,
  }) async {
    final size = (await file.stat()).size;
    await pipeChunks(
      statSize: size,
      read: (length, offset) =>
          file.readBytes(length: length, offset: offset),
      add: sink.add,
      onProgress: onProgress,
    );
  }

  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      final items = await sftp.listdir(path);
      final visible = [
        for (final item in items)
          if (item.filename != '.' && item.filename != '..') item,
      ];
      // Resolve symlink targets so symlink-to-dir entries navigate instead of
      // being read as files (which servers answer with SSH_FX_FAILURE).
      final isDir = await Future.wait(visible.map(
        (item) => resolveEntryIsDirectory(
          attr: item.attr,
          path: p.posix.join(path, item.filename),
          stat: sftp.stat,
        ),
      ));
      return [
        for (final (i, item) in visible.indexed)
          SftpEntry(
            name: item.filename,
            path: p.posix.join(path, item.filename),
            isDirectory: isDir[i],
            size: item.attr.size ?? 0,
            mode: item.attr.mode?.value,
            modifiedAt: item.attr.modifyTime != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    item.attr.modifyTime! * 1000)
                : DateTime.now(),
          ),
      ];
    } finally {
      sftp.close();
    }
  }

  Future<String?> downloadToTemp(Host host, SftpEntry entry) async {
    final sftp = await _sshService.openSftp(host);
    final tmpDir = await getTemporaryDirectory();
    final localPath = p.join(tmpDir.path, entry.name);
    SftpFile? file;
    final sink = File(localPath).openWrite();
    try {
      file = await sftp.open(entry.path);
      await _pipeToSink(file, sink);
    } finally {
      await sink.close();
      await file?.close();
      sftp.close();
    }
    return localPath;
  }

  Future<void> uploadFile(Host host, String localPath, String remotePath,
      {void Function(int sent, int total)? onProgress}) async {
    final sftp = await _sshService.openSftp(host);
    SftpFile? remoteFile;
    try {
      final total = await File(localPath).length();
      remoteFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      int offset = 0;
      await for (final chunk in File(localPath).openRead()) {
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await remoteFile.writeBytes(bytes, offset: offset);
        offset += bytes.length;
        onProgress?.call(offset, total);
      }
    } finally {
      await remoteFile?.close();
      sftp.close();
    }
  }

  Future<void> copyLocalToRemote({
    required String localPath,
    required Host remoteHost,
    required String remoteDir,
  }) async {
    final fileName = p.basename(localPath);
    final remotePath = p.posix.join(remoteDir, fileName);
    await uploadFile(remoteHost, localPath, remotePath);
  }

  Future<void> copyRemoteToLocal({
    required Host remoteHost,
    required SftpEntry remoteEntry,
    required String localDir,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    SftpFile? remoteFile;
    final sink = File(p.join(localDir, remoteEntry.name)).openWrite();
    try {
      remoteFile = await sftp.open(remoteEntry.path);
      await _pipeToSink(remoteFile, sink);
    } finally {
      await sink.close();
      await remoteFile?.close();
      sftp.close();
    }
  }

  Future<void> uploadDirectory({
    required String localDir,
    required Host remoteHost,
    required String remoteDir,
    required void Function(String filePath, int bytes, int total) onProgress,
    required void Function(String filePath) onFileSkipped,
    required bool Function() isCancelled,
    bool overwrite = false,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    try {
      await _uploadDirRecursive(
        sftp: sftp,
        localDir: localDir,
        remoteDir: remoteDir,
        onProgress: onProgress,
        onFileSkipped: onFileSkipped,
        isCancelled: isCancelled,
        overwrite: overwrite,
      );
    } finally {
      sftp.close();
    }
  }

  Future<void> _uploadDirRecursive({
    required SftpClient sftp,
    required String localDir,
    required String remoteDir,
    required void Function(String, int, int) onProgress,
    required void Function(String) onFileSkipped,
    required bool Function() isCancelled,
    required bool overwrite,
  }) async {
    // mkdir often fails because the dir already exists — that's fine. Anything
    // else (e.g., SSH_FX_PERMISSION_DENIED) we want to surface so the user
    // doesn't get a confusing later error from the file write.
    try {
      await sftp.mkdir(remoteDir);
    } on SftpStatusError catch (e) {
      // 4 = generic failure, 11 = "file already exists" (FX_FILE_ALREADY_EXISTS)
      // are both expected for "directory exists". Anything else is fatal.
      if (e.code != SftpStatusCode.failure && e.code != 11) rethrow;
    }
    final entities = await Directory(localDir).list().toList();
    for (final entity in entities) {
      if (isCancelled()) return;
      final name = p.basename(entity.path);
      final remotePath = p.posix.join(remoteDir, name);
      if (entity is Directory) {
        await _uploadDirRecursive(
          sftp: sftp, localDir: entity.path, remoteDir: remotePath,
          onProgress: onProgress, onFileSkipped: onFileSkipped,
          isCancelled: isCancelled, overwrite: overwrite,
        );
      } else {
        if (!overwrite) {
          // stat: only treat "no such file" as "needs upload". Permission / I/O
          // errors are surfaced so we don't silently overwrite or silently skip.
          bool fileExists;
          try {
            await sftp.stat(remotePath);
            fileExists = true;
          } on SftpStatusError catch (e) {
            if (e.code == SftpStatusCode.noSuchFile) {
              fileExists = false;
            } else {
              rethrow;
            }
          }
          if (fileExists) {
            onFileSkipped(entity.path);
            continue;
          }
        }
        await _uploadFileWithProgress(sftp, entity.path, remotePath, onProgress);
      }
    }
  }

  Future<void> _uploadFileWithProgress(
    SftpClient sftp,
    String localPath,
    String remotePath,
    void Function(String, int, int) onProgress,
  ) async {
    final localFile = File(localPath);
    final total = await localFile.length();
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    try {
      int offset = 0;
      await for (final chunk in localFile.openRead()) {
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await remoteFile.writeBytes(bytes, offset: offset);
        offset += bytes.length;
        onProgress(localPath, offset, total);
      }
    } finally {
      await remoteFile.close();
    }
  }

  Future<void> downloadDirectory({
    required Host remoteHost,
    required SftpEntry remoteDir,
    required String localDir,
    required void Function(String filePath, int bytes, int total) onProgress,
    required void Function(String filePath) onFileSkipped,
    required bool Function() isCancelled,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    try {
      await _downloadDirRecursive(
        sftp: sftp,
        remotePath: remoteDir.path,
        localDir: localDir,
        onProgress: onProgress,
        onFileSkipped: onFileSkipped,
        isCancelled: isCancelled,
      );
    } finally {
      sftp.close();
    }
  }

  Future<void> _downloadDirRecursive({
    required SftpClient sftp,
    required String remotePath,
    required String localDir,
    required void Function(String, int, int) onProgress,
    required void Function(String) onFileSkipped,
    required bool Function() isCancelled,
  }) async {
    final dest = Directory(p.join(localDir, p.posix.basename(remotePath)));
    if (!await dest.exists()) await dest.create(recursive: true);
    final items = await sftp.listdir(remotePath);
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      if (isCancelled()) return;
      final childRemote = p.posix.join(remotePath, item.filename);
      // Resolve symlinks the same way the panel listing does, so a
      // symlink-to-dir shown as a folder in the UI is recursed into rather
      // than downloaded as a file.
      final isDirEntry = await resolveEntryIsDirectory(
        attr: item.attr,
        path: childRemote,
        stat: sftp.stat,
      );
      if (isDirEntry) {
        await _downloadDirRecursive(
          sftp: sftp, remotePath: childRemote, localDir: dest.path,
          onProgress: onProgress, onFileSkipped: onFileSkipped, isCancelled: isCancelled,
        );
      } else {
        final localPath = p.join(dest.path, item.filename);
        if (await File(localPath).exists()) { onFileSkipped(childRemote); continue; }
        await _downloadFileWithProgress(sftp, childRemote, localPath, item.attr.size ?? 0, onProgress);
      }
    }
  }

  Future<void> _downloadFileWithProgress(
    SftpClient sftp,
    String remotePath,
    String localPath,
    int totalBytes,
    void Function(String, int, int) onProgress,
  ) async {
    final remoteFile = await sftp.open(remotePath);
    final sink = File(localPath).openWrite();
    try {
      await _pipeToSink(remoteFile, sink,
          onProgress: (offset) => onProgress(
              remotePath, offset, totalBytes > 0 ? totalBytes : offset));
    } finally {
      await sink.close();
      await remoteFile.close();
    }
  }
}
