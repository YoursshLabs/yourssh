// app/lib/util/private_temp.dart
import 'dart:io';

import 'file_mode.dart';

const int _ownerOnlyDir = 0x1C0; // 0700
const int _ownerOnlyFile = 0x180; // 0600

/// Restricts [dir] to 0700 and, when given, [file] to 0600. No-op on Windows
/// (per-user temp ACLs already apply). Throws when chmod fails so callers
/// never carry on with a world-readable copy of remote data.
Future<void> restrictToOwner({Directory? dir, File? file}) async {
  if (Platform.isWindows) return;
  if (dir != null) await chmodLocal(dir.path, _ownerOnlyDir);
  if (file != null) await chmodLocal(file.path, _ownerOnlyFile);
}

/// Creates a fresh, randomly named, owner-only directory under [parent].
Future<Directory> createPrivateTempDir(Directory parent, String prefix) async {
  final dir = await parent.createTemp(prefix);
  try {
    await restrictToOwner(dir: dir);
  } catch (_) {
    await dir.delete(recursive: true);
    rethrow;
  }
  return dir;
}
