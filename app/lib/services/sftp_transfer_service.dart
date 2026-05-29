// app/lib/services/sftp_transfer_service.dart
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import 'ssh_service.dart';

class SftpTransferService {
  final SshService _sshService;

  SftpTransferService(this._sshService);

  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    final items = await sftp.listdir(path);
    sftp.close();

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
  }

  Future<String?> downloadToTemp(Host host, SftpEntry entry) async {
    final sftp = await _sshService.openSftp(host);
    final tmpDir = await getTemporaryDirectory();
    final localPath = p.join(tmpDir.path, entry.name);
    final file = await sftp.open(entry.path);
    final bytes = await file.readBytes();
    await File(localPath).writeAsBytes(bytes);
    await file.close();
    sftp.close();
    return localPath;
  }

  Future<void> uploadFile(
      Host host, String localPath, String remotePath) async {
    final sftp = await _sshService.openSftp(host);
    final bytes = await File(localPath).readAsBytes();
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    await remoteFile.writeBytes(bytes);
    await remoteFile.close();
    sftp.close();
  }

  Future<void> copyBetweenPanels({
    required Host sourceHost,
    required SftpEntry sourceEntry,
    required Host destinationHost,
    required String destinationPath,
  }) async {
    final tmpPath = await downloadToTemp(sourceHost, sourceEntry);
    if (tmpPath == null) return;
    final destFilePath = p.posix.join(destinationPath, sourceEntry.name);
    await uploadFile(destinationHost, tmpPath, destFilePath);
    await File(tmpPath).delete();
  }
}
