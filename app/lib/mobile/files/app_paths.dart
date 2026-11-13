import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../platform/runtime_platform.dart';
import '../../util/file_mode.dart';
import '../../util/native_chmod.dart';

/// `chmod(path, mode)`; same shape as the `KeyGenService` constructor type.
typedef ChmodFn = Future<void> Function(String path, int mode);

const MethodChannel _filesChannel = MethodChannel('yourssh/files');

Future<void> _defaultExcludeFromBackup(String path) async {
  if (!isIOSPlatform) return;
  await _filesChannel.invokeMethod<void>('excludeFromBackup', path);
}

/// Where the mobile app keeps its files.
///
/// On iOS the Documents directory is shown in the Files app
/// (`UIFileSharingEnabled`), so private keys must live elsewhere: in the
/// Application Support directory, which is neither exposed nor — once the
/// directory is flagged — backed up.
class AppPaths {
  AppPaths._();

  /// Directory name of the private keys dir inside Application Support.
  static const keysDirName = 'keys';

  /// Path of [privateKeysDir] without creating it or touching its mode.
  static Future<String> privateKeysDirPath() async =>
      p.join((await getApplicationSupportDirectory()).path, keysDirName);

  /// `<ApplicationSupport>/keys`: created, 0700, excluded from backups.
  static Future<Directory> privateKeysDir({
    ChmodFn? chmod,
    Future<void> Function(String path)? excludeFromBackup,
  }) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, keysDirName));
    await dir.create(recursive: true);
    await (chmod ?? (supportsSubprocesses ? chmodLocal : chmodNative))(
        dir.path, 0x1C0);
    await (excludeFromBackup ?? _defaultExcludeFromBackup)(dir.path);
    return dir;
  }

  /// `<Documents>/Downloads`: the only folder the Files app shows for us.
  static Future<Directory> downloadsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Downloads'));
    await dir.create(recursive: true);
    return dir;
  }
}
