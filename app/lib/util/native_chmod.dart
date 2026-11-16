import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `chmod(2)` through libc, for platforms that cannot spawn the `chmod`
/// binary (iOS). Not supported on Windows.
///
/// `mode_t` is 16 bits on Darwin and 32 bits on Linux/Android.
Future<void> chmodNative(String path, int mode) async {
  if (Platform.isWindows) {
    throw UnsupportedError('chmodNative is not supported on Windows');
  }
  final lib = DynamicLibrary.process();
  final errnoLocation = lib.lookupFunction<Pointer<Int32> Function(),
      Pointer<Int32> Function()>(
    Platform.isIOS || Platform.isMacOS ? '__error' : '__errno_location',
  );
  final cPath = path.toNativeUtf8();
  try {
    final int rc;
    if (Platform.isIOS || Platform.isMacOS) {
      rc = lib.lookupFunction<Int32 Function(Pointer<Utf8>, Uint16),
          int Function(Pointer<Utf8>, int)>('chmod')(cPath, mode);
    } else {
      rc = lib.lookupFunction<Int32 Function(Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, int)>('chmod')(cPath, mode);
    }
    if (rc != 0) {
      final errno = errnoLocation().value;
      throw FileSystemException('chmod failed', path, OSError('', errno));
    }
  } finally {
    calloc.free(cPath);
  }
}
