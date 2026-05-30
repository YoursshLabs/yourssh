// app/lib/services/sftp_transfer_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import 'ssh_service.dart';

class SftpTransferService {
  final SshService _sshService;

  SftpTransferService(this._sshService);

  static const _chunkSize = 64 * 1024;

  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      final items = await sftp.listdir(path);
      return items
          .where((item) => item.filename != '.' && item.filename != '..')
          .map((item) => SftpEntry(
                name: item.filename,
                path: p.posix.join(path, item.filename),
                isDirectory: item.attr.isDirectory,
                size: item.attr.size ?? 0,
                modifiedAt: item.attr.modifyTime != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        item.attr.modifyTime! * 1000)
                    : DateTime.now(),
              ))
          .toList();
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
      int offset = 0;
      while (true) {
        final chunk = await file.readBytes(length: _chunkSize, offset: offset);
        if (chunk.isEmpty) break;
        sink.add(chunk);
        offset += chunk.length;
      }
    } finally {
      await sink.close();
      await file?.close();
      sftp.close();
    }
    return localPath;
  }

  Future<void> uploadFile(
      Host host, String localPath, String remotePath) async {
    final sftp = await _sshService.openSftp(host);
    SftpFile? remoteFile;
    try {
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
      int offset = 0;
      while (true) {
        final chunk = await remoteFile.readBytes(length: _chunkSize, offset: offset);
        if (chunk.isEmpty) break;
        sink.add(chunk);
        offset += chunk.length;
      }
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
  }) async {
    try { await sftp.mkdir(remoteDir); } catch (_) {}
    final entities = await Directory(localDir).list().toList();
    for (final entity in entities) {
      if (isCancelled()) return;
      final name = p.basename(entity.path);
      final remotePath = p.posix.join(remoteDir, name);
      if (entity is Directory) {
        await _uploadDirRecursive(
          sftp: sftp, localDir: entity.path, remoteDir: remotePath,
          onProgress: onProgress, onFileSkipped: onFileSkipped, isCancelled: isCancelled,
        );
      } else {
        try { await sftp.stat(remotePath); onFileSkipped(entity.path); continue; } catch (_) {}
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
      if (item.attr.isDirectory) {
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
      int offset = 0;
      while (true) {
        final chunk = await remoteFile.readBytes(length: _chunkSize, offset: offset);
        if (chunk.isEmpty) break;
        sink.add(chunk);
        offset += chunk.length;
        onProgress(remotePath, offset, totalBytes > 0 ? totalBytes : offset);
      }
    } finally {
      await sink.close();
      await remoteFile.close();
    }
  }
}
