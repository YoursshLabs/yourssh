import 'dart:io';
import 'package:path/path.dart' as p;

/// Turns a `dart:io` filesystem failure into a sentence a user can act on.
///
/// The raw exception is useless in the UI — `PathAccessException: Directory
/// listing failed, path = '…' (OS Error: Operation not permitted, errno = 1)`
/// tells nobody that macOS is gating the folder behind a privacy permission.
String describeFileSystemError(Object error, {required String path}) {
  final name = p.basename(path).isEmpty ? path : p.basename(path);
  if (error is FileSystemException) {
    final errno = error.osError?.errorCode;
    if (error is PathNotFoundException || errno == 2) {
      return '"$name" no longer exists.';
    }
    // EPERM (sandbox / macOS privacy denial) and EACCES (POSIX mode).
    if (error is PathAccessException || errno == 1 || errno == 13) {
      return 'Access to "$name" was denied.\nGrant access in System Settings → '
          'Privacy & Security → Files and Folders (or Full Disk Access).';
    }
    return error.message;
  }
  return error.toString();
}
