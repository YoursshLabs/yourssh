import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Linux `SO_PEERCRED` result: `struct ucred {int pid; uint uid; uint gid}`.
/// macOS `LOCAL_PEERCRED` result: `struct xucred {u_int cr_version; uid_t
/// cr_uid; ...}`. Returns the peer uid, or null when [raw] is malformed.
int? peerUidFromCred(Uint8List raw, String os) {
  if (raw.lengthInBytes < 8) return null;
  final d = ByteData.sublistView(raw);
  switch (os) {
    case 'linux':
      return d.getUint32(4, Endian.host);
    case 'macos':
      if (d.getUint32(0, Endian.host) != 0) return null; // XUCRED_VERSION
      return d.getUint32(4, Endian.host);
  }
  return null;
}

/// The uid this process runs as (POSIX only).
int currentUid() {
  final getuid = DynamicLibrary.process()
      .lookupFunction<Uint32 Function(), int Function()>('getuid');
  return getuid();
}

/// Uid of the process on the other end of an accepted unix-domain [socket],
/// or null when it cannot be determined (callers must treat that as denied).
int? peerUidOf(Socket socket) {
  try {
    if (Platform.isLinux) {
      // SOL_SOCKET = 1, SO_PEERCRED = 17, sizeof(struct ucred) = 12.
      final raw = socket.getRawOption(RawSocketOption(1, 17, Uint8List(12)));
      return peerUidFromCred(raw, 'linux');
    }
    if (Platform.isMacOS) {
      // SOL_LOCAL = 0, LOCAL_PEERCRED = 1, sizeof(struct xucred) = 76.
      final raw = socket.getRawOption(RawSocketOption(0, 1, Uint8List(76)));
      return peerUidFromCred(raw, 'macos');
    }
  } catch (_) {}
  return null;
}
