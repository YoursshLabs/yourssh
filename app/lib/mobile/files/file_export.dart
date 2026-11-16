import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../platform/runtime_platform.dart';
import '../../util/file_mode.dart';
import '../../util/native_chmod.dart';
import '../../util/safe_local_path.dart';
import 'app_paths.dart';

/// Copies (never moves) a picked private key into [into] under a unique,
/// sanitized name with mode 0600, and returns the copy.
Future<File> importPrivateKey(
  String pickedPath,
  Directory into, {
  ChmodFn? chmod,
}) async {
  final base = p
      .basename(pickedPath)
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
      .replaceFirst(RegExp(r'^\.+'), '_');
  final target = uniqueLocalPath(into.path, base.isEmpty ? 'key' : base);
  final chmodFn = chmod ?? (supportsSubprocesses ? chmodLocal : chmodNative);
  // Create empty and restrict before any key bytes land.
  final out = await File(target).create(exclusive: true);
  try {
    await chmodFn(out.path, 0x180);
    await out.writeAsBytes(await File(pickedPath).readAsBytes());
  } catch (_) {
    if (out.existsSync()) await out.delete();
    rethrow;
  }
  return out;
}

/// [name] inside [dir] (validated by [safeLocalChild]); when taken, the
/// first free `name (1).ext`, `name (2).ext`, ...
String uniqueLocalPath(String dir, String name) {
  final first = safeLocalChild(dir, name);
  if (!_exists(first)) return first;
  final ext = p.extension(name);
  final stem = ext.isEmpty ? name : name.substring(0, name.length - ext.length);
  for (var i = 1;; i++) {
    final candidate = safeLocalChild(dir, '$stem ($i)$ext');
    if (!_exists(candidate)) return candidate;
  }
}

bool _exists(String path) => FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

/// Streams [data] into `finalPath.part` and renames it to [finalPath] on
/// success. On any error the partial file is deleted and the error rethrown,
/// so a failed download never leaves a truncated file behind.
Future<void> writeDownload(Stream<List<int>> data, String finalPath) async {
  final part = File('$finalPath.part');
  final sink = part.openWrite();
  try {
    await sink.addStream(data);
    await sink.close();
    await part.rename(finalPath);
  } catch (_) {
    try {
      await sink.close();
    } catch (_) {}
    try {
      if (part.existsSync()) await part.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Opens the iOS share sheet for [path].
Future<void> shareFile(BuildContext context, String path) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  await Share.shareXFiles([XFile(path)], sharePositionOrigin: origin);
}
