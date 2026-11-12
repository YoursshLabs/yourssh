/// Hand-written Win32 bindings (kernel32 / advapi32 / ntdll) for the YourSSH
/// CLI named pipe, shared by the app's listener and the `yourssh` client.
///
/// Nothing loads a DLL until the first call, so importing this library is
/// safe on macOS and Linux.
///
/// R25: no decision depends on `GetLastError`. Under the Dart VM it reads 0
/// (the VM's own transitions reset it), so it only feeds message text.
/// Decisions come from:
/// - return values (handles, BOOL);
/// - NTSTATUS codes: pipe I/O goes through `NtFsControlFile(FSCTL_PIPE_LISTEN)`,
///   `NtReadFile` and `NtWriteFile`, which return the status that kernel32
///   would only store in the last error, and the completion status in the
///   IO_STATUS_BLOCK (the head of OVERLAPPED) once an operation finishes;
/// - [pipeExists], which lists `\\.\pipe\` (never opening the pipe itself).
///
/// The kernel32 wrappers can't be used for overlapped pipe I/O without
/// GetLastError: they set `OVERLAPPED.Internal` to STATUS_PENDING before
/// issuing the request, so a synchronous failure (no event, no status
/// written) looks exactly like a pending operation.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Directory, FileSystemException;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A Win32 call failed. [code] is the last error or NTSTATUS, for the
/// message only: never branch on it (R25).
class WinPipeException implements Exception {
  const WinPipeException(this.op, [this.code = 0]);
  final String op;
  final int code;
  @override
  String toString() =>
      'WinPipeException: $op failed (0x${code.toRadixString(16)})';
}

// ---------------------------------------------------------------------------
// Constants (winbase.h / winnt.h / fileapi.h / synchapi.h / sddl.h /
// winioctl.h / ntstatus.h)

const int _invalidHandleValue = -1; // INVALID_HANDLE_VALUE
const int _pipeAccessDuplex = 0x00000003; // PIPE_ACCESS_DUPLEX
const int _fileFlagFirstPipeInstance = 0x00080000; // FILE_FLAG_FIRST_PIPE_INSTANCE
const int _fileFlagOverlapped = 0x40000000; // FILE_FLAG_OVERLAPPED
const int _pipeTypeByte = 0x00000000; // PIPE_TYPE_BYTE
const int _pipeReadmodeByte = 0x00000000; // PIPE_READMODE_BYTE
const int _pipeWait = 0x00000000; // PIPE_WAIT
const int _pipeRejectRemoteClients = 0x00000008; // PIPE_REJECT_REMOTE_CLIENTS
const int _pipeUnlimitedInstances = 255; // PIPE_UNLIMITED_INSTANCES
const int _genericRead = 0x80000000; // GENERIC_READ
const int _genericWrite = 0x40000000; // GENERIC_WRITE
const int _openExisting = 3; // OPEN_EXISTING
const int _securitySqosPresent = 0x00100000; // SECURITY_SQOS_PRESENT
const int _securityIdentification = 0x00010000; // SecurityIdentification << 16
const int _infinite = 0xFFFFFFFF; // INFINITE
const int _waitObject0 = 0x00000000; // WAIT_OBJECT_0
const int _waitTimeout = 0x00000102; // WAIT_TIMEOUT
const int _processQueryLimitedInformation = 0x1000;
const int _tokenQuery = 0x0008; // TOKEN_QUERY
const int _tokenUserClass = 1; // TOKEN_INFORMATION_CLASS.TokenUser
const int _sddlRevision1 = 1; // SDDL_REVISION_1

/// CTL_CODE(FILE_DEVICE_NAMED_PIPE 0x11, 2, METHOD_BUFFERED, FILE_ANY_ACCESS).
const int _fsctlPipeListen = 0x00110008;

/// NTSTATUS values (ntstatus.h; MS-ERREF 2.3.1).
abstract final class NtStatus {
  static const success = 0x00000000; // STATUS_SUCCESS
  static const pending = 0x00000103; // STATUS_PENDING
  static const endOfFile = 0xC0000011; // STATUS_END_OF_FILE
  static const pipeDisconnected = 0xC00000B0; // STATUS_PIPE_DISCONNECTED
  static const pipeClosing = 0xC00000B1; // STATUS_PIPE_CLOSING
  static const pipeConnected = 0xC00000B2; // STATUS_PIPE_CONNECTED
  static const pipeBroken = 0xC000014B; // STATUS_PIPE_BROKEN
  static const cancelled = 0xC0000120; // STATUS_CANCELLED
}

/// The other end is gone (or going): treat as a lost connection.
bool _isClosedStatus(int status) =>
    status == NtStatus.pipeBroken ||
    status == NtStatus.pipeDisconnected ||
    status == NtStatus.pipeClosing ||
    status == NtStatus.endOfFile;

/// One I/O chunk; also the pipe's advisory in/out buffer size.
const int _chunk = 64 * 1024;

const String _pipePrefix = r'\\.\pipe\';

// ---------------------------------------------------------------------------
// Structs

/// `OVERLAPPED` (minwinbase.h): two ULONG_PTR, a union of two DWORDs with a
/// PVOID (8 bytes on every Windows ABI), then the event HANDLE. 32 bytes on
/// x64/arm64. Its first two fields are the IO_STATUS_BLOCK (Status,
/// Information) the Nt* calls fill in, exactly as kernel32 passes it.
final class _Overlapped extends Struct {
  @IntPtr()
  external int internal;
  @IntPtr()
  external int internalHigh;
  @Uint32()
  external int offset;
  @Uint32()
  external int offsetHigh;
  @IntPtr()
  external int hEvent;
}

/// `SECURITY_ATTRIBUTES` (minwinbase.h): DWORD nLength, LPVOID
/// lpSecurityDescriptor, BOOL bInheritHandle. 24 bytes on x64/arm64; nLength
/// is set from sizeOf.
final class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;
  external Pointer<Void> lpSecurityDescriptor;
  @Int32()
  external int bInheritHandle;
}

// ---------------------------------------------------------------------------
// Bindings. HANDLE = IntPtr, DWORD/ULONG = Uint32, BOOL = Int32, NTSTATUS =
// Int32 (normalised with & 0xFFFFFFFF). Calls touching the pipe or the I/O
// manager are not leaf calls (a stuck leaf call would hold up GC for the
// isolate group); pure in-memory helpers are.

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');
final DynamicLibrary _ntdll = DynamicLibrary.open('ntdll.dll');

// Message text only (R25).
final _getLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
    isLeaf: true);

final _closeHandle =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle');

final _createNamedPipeW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Uint32, Uint32, Uint32,
        Uint32, Pointer<_SecurityAttributes>),
    int Function(Pointer<Utf16>, int, int, int, int, int, int,
        Pointer<_SecurityAttributes>)>('CreateNamedPipeW');

final _disconnectNamedPipe =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'DisconnectNamedPipe');

final _createFileW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Uint32, Uint32,
        Pointer<_SecurityAttributes>, Uint32, Uint32, IntPtr),
    int Function(Pointer<Utf16>, int, int, Pointer<_SecurityAttributes>, int,
        int, int)>('CreateFileW');

final _waitNamedPipeW = _kernel32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32),
    int Function(Pointer<Utf16>, int)>('WaitNamedPipeW');

final _cancelIoEx = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>),
    int Function(int, Pointer<_Overlapped>)>('CancelIoEx');

final _createEventW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<_SecurityAttributes>, Int32, Int32, Pointer<Utf16>),
    int Function(Pointer<_SecurityAttributes>, int, int,
        Pointer<Utf16>)>('CreateEventW');

final _setEvent =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetEvent');

final _resetEvent =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'ResetEvent');

final _waitForMultipleObjects = _kernel32.lookupFunction<
    Uint32 Function(Uint32, Pointer<IntPtr>, Int32, Uint32),
    int Function(int, Pointer<IntPtr>, int, int)>('WaitForMultipleObjects');

final _getNamedPipeClientProcessId = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetNamedPipeClientProcessId');

final _getNamedPipeServerProcessId = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetNamedPipeServerProcessId');

final _getCurrentProcess =
    _kernel32.lookupFunction<IntPtr Function(), int Function()>(
        'GetCurrentProcess',
        isLeaf: true);

final _openProcess = _kernel32.lookupFunction<
    IntPtr Function(Uint32, Int32, Uint32),
    int Function(int, int, int)>('OpenProcess');

final _localFree = _kernel32.lookupFunction<IntPtr Function(Pointer<Void>),
    int Function(Pointer<Void>)>('LocalFree', isLeaf: true);

final _openProcessToken = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
    int Function(int, int, Pointer<IntPtr>)>('OpenProcessToken');

final _getTokenInformation = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
    int Function(int, int, Pointer<Void>, int,
        Pointer<Uint32>)>('GetTokenInformation');

final _convertSidToStringSidW = _advapi32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>),
    int Function(Pointer<Void>, Pointer<Pointer<Utf16>>)>(
    'ConvertSidToStringSidW',
    isLeaf: true);

final _convertStringSdToSd = _advapi32.lookupFunction<
        Int32 Function(
            Pointer<Utf16>, Uint32, Pointer<Pointer<Void>>, Pointer<Uint32>),
        int Function(
            Pointer<Utf16>, int, Pointer<Pointer<Void>>, Pointer<Uint32>)>(
    'ConvertStringSecurityDescriptorToSecurityDescriptorW',
    isLeaf: true);

final _equalSid = _advapi32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Void>)>('EqualSid', isLeaf: true);

// NTSTATUS NtFsControlFile(HANDLE FileHandle, HANDLE Event,
//   PIO_APC_ROUTINE ApcRoutine, PVOID ApcContext, PIO_STATUS_BLOCK
//   IoStatusBlock, ULONG FsControlCode, PVOID InputBuffer, ULONG
//   InputBufferLength, PVOID OutputBuffer, ULONG OutputBufferLength)
final _ntFsControlFile = _ntdll.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Pointer<Void>, Pointer<Void>,
        Pointer<_Overlapped>, Uint32, Pointer<Void>, Uint32, Pointer<Void>,
        Uint32),
    int Function(int, int, Pointer<Void>, Pointer<Void>, Pointer<_Overlapped>,
        int, Pointer<Void>, int, Pointer<Void>, int)>('NtFsControlFile');

// NTSTATUS NtReadFile / NtWriteFile(HANDLE FileHandle, HANDLE Event,
//   PIO_APC_ROUTINE ApcRoutine, PVOID ApcContext, PIO_STATUS_BLOCK
//   IoStatusBlock, PVOID Buffer, ULONG Length, PLARGE_INTEGER ByteOffset,
//   PULONG Key)
typedef _NtIoNative = Int32 Function(IntPtr, IntPtr, Pointer<Void>,
    Pointer<Void>, Pointer<_Overlapped>, Pointer<Uint8>, Uint32,
    Pointer<Int64>, Pointer<Uint32>);
typedef _NtIoDart = int Function(int, int, Pointer<Void>, Pointer<Void>,
    Pointer<_Overlapped>, Pointer<Uint8>, int, Pointer<Int64>, Pointer<Uint32>);

final _ntReadFile =
    _ntdll.lookupFunction<_NtIoNative, _NtIoDart>('NtReadFile');
final _ntWriteFile =
    _ntdll.lookupFunction<_NtIoNative, _NtIoDart>('NtWriteFile');

// ---------------------------------------------------------------------------
// Users and security

final RegExp _sidPattern = RegExp(r'^S-1-\d+(-\d+)+$');

/// SDDL for the pipe: a protected DACL with one entry granting GENERIC_ALL to
/// [sid] (read/write plus FILE_CREATE_PIPE_INSTANCE, which the server needs
/// for every further instance). Nobody else, not even SYSTEM or
/// Administrators, gets an entry. Throws [ArgumentError] unless [sid] is a
/// SID string, so nothing can be spliced into the descriptor.
String pipeSddlForSid(String sid) {
  if (!_sidPattern.hasMatch(sid)) {
    throw ArgumentError.value(sid, 'sid', 'not a SID string');
  }
  return 'D:P(A;;GA;;;$sid)';
}

/// The string SID (`S-1-5-21-…`) of the user this process runs as.
String currentUserSid() => using((arena) {
      final token = _openTokenOf(_getCurrentProcess());
      try {
        return _sidToString(_tokenUserSid(token, arena));
      } finally {
        _closeHandle(token);
      }
    });

/// True when process [pid] runs as the same user as this process (EqualSid
/// of both tokens' TokenUser). Any failure (no such process, no access to
/// its token) is false.
bool processRunsAsCurrentUser(int pid) {
  if (pid <= 0) return false;
  try {
    return using((arena) {
      final own = _openTokenOf(_getCurrentProcess());
      try {
        final ours = _tokenUserSid(own, arena);
        final process = _openProcess(_processQueryLimitedInformation, 0, pid);
        if (process == 0) return false;
        try {
          final token = _openTokenOf(process);
          try {
            return _equalSid(ours, _tokenUserSid(token, arena)) != 0;
          } finally {
            _closeHandle(token);
          }
        } finally {
          _closeHandle(process);
        }
      } finally {
        _closeHandle(own);
      }
    });
  } on WinPipeException {
    return false;
  }
}

/// TOKEN_QUERY handle of [process]; throws on failure.
int _openTokenOf(int process) {
  final out = calloc<IntPtr>();
  try {
    if (_openProcessToken(process, _tokenQuery, out) == 0) {
      throw WinPipeException('OpenProcessToken', _getLastError());
    }
    return out.value;
  } finally {
    calloc.free(out);
  }
}

/// The SID in [token]'s TokenUser. The SID lives in an [arena] buffer. A
/// too-small buffer is detected from ReturnLength, not the last error.
Pointer<Void> _tokenUserSid(int token, Arena arena) {
  final needed = arena<Uint32>();
  var size = 256;
  for (var attempt = 0; attempt < 2; attempt++) {
    final buf = arena<Uint8>(size);
    needed.value = 0;
    if (_getTokenInformation(token, _tokenUserClass, buf.cast(), size, needed) !=
        0) {
      // TOKEN_USER { SID_AND_ATTRIBUTES User { PSID Sid; DWORD Attributes } }
      return buf.cast<Pointer<Void>>().value;
    }
    if (needed.value <= size) break; // not a size problem
    size = needed.value;
  }
  throw WinPipeException('GetTokenInformation', _getLastError());
}

String _sidToString(Pointer<Void> sid) {
  final out = calloc<Pointer<Utf16>>();
  try {
    if (_convertSidToStringSidW(sid, out) == 0) {
      throw WinPipeException('ConvertSidToStringSidW', _getLastError());
    }
    try {
      return out.value.toDartString();
    } finally {
      _localFree(out.value.cast());
    }
  } finally {
    calloc.free(out);
  }
}

/// Runs [body] with SECURITY_ATTRIBUTES whose DACL is [pipeSddlForSid]. The
/// descriptor is freed (LocalFree) afterwards; CreateNamedPipeW copies it.
T _withPipeSecurity<T>(
    String sid, T Function(Pointer<_SecurityAttributes> sa) body) {
  final sddl = pipeSddlForSid(sid);
  return using((arena) {
    final sd = arena<Pointer<Void>>();
    if (_convertStringSdToSd(
            sddl.toNativeUtf16(allocator: arena), _sddlRevision1, sd, nullptr) ==
        0) {
      throw WinPipeException(
          'ConvertStringSecurityDescriptorToSecurityDescriptorW',
          _getLastError());
    }
    try {
      final sa = arena<_SecurityAttributes>();
      sa.ref
        ..nLength = sizeOf<_SecurityAttributes>()
        ..lpSecurityDescriptor = sd.value
        ..bInheritHandle = 0;
      return body(sa);
    } finally {
      _localFree(sd.value);
    }
  });
}

// ---------------------------------------------------------------------------
// Pipe names

/// True when a pipe named [name] (`\\.\pipe\…`, case-insensitive) exists.
/// Lists `\\.\pipe\` (FindFirstFile on the pipe namespace) and never opens
/// or stats [name] itself, which would consume a listening instance.
bool pipeExists(String name) {
  if (name.length <= _pipePrefix.length ||
      name.substring(0, _pipePrefix.length).toLowerCase() !=
          _pipePrefix.toLowerCase()) {
    return false;
  }
  final want = name.substring(_pipePrefix.length).toLowerCase();
  try {
    for (final e in Directory(_pipePrefix).listSync(followLinks: false)) {
      final path = e.path;
      final rest = path.length > _pipePrefix.length &&
              path.substring(0, _pipePrefix.length).toLowerCase() ==
                  _pipePrefix.toLowerCase()
          ? path.substring(_pipePrefix.length)
          : path.substring(path.lastIndexOf('\\') + 1);
      if (rest.toLowerCase() == want) return true;
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Handles and events

/// A manual-reset, initially non-signalled event (the listener's stop
/// signal). Close it with [closeWinHandle].
int createStopEvent() {
  final h = _createEventW(nullptr, 1, 0, nullptr);
  if (h == 0) throw WinPipeException('CreateEventW', _getLastError());
  return h;
}

void signalEvent(int event) => _setEvent(event);

/// Waits up to [timeoutMs] for [event]; true when it is signalled.
bool waitForEvent(int event, {required int timeoutMs}) {
  final handles = calloc<IntPtr>();
  try {
    handles.value = event;
    return _waitForMultipleObjects(1, handles, 0, timeoutMs) == _waitObject0;
  } finally {
    calloc.free(handles);
  }
}

void closeWinHandle(int handle) {
  if (handle != 0 && handle != _invalidHandleValue) _closeHandle(handle);
}

// ---------------------------------------------------------------------------
// Overlapped I/O

/// How a pipe operation ended.
enum PipeIoEnd {
  /// Write: every byte was written.
  done,

  /// Read: a newline arrived.
  newline,

  /// The other end closed (or the pipe broke).
  closed,

  /// Read: more than `maxBytes` before a newline.
  tooLong,
  timeout,

  /// The stop event fired.
  stopped,
  failed,
}

/// One IO_STATUS_BLOCK (in an OVERLAPPED) + event for a sequence of
/// operations on [pipe]. Every operation is finished, or cancelled and
/// waited for, before [run] returns, so the structure is never freed or
/// reused under a pending I/O.
class _Io {
  _Io(this.pipe) {
    final ev = _createEventW(nullptr, 1, 0, nullptr);
    if (ev == 0) {
      final err = _getLastError();
      _free();
      throw WinPipeException('CreateEventW', err);
    }
    ov.ref.hEvent = ev;
  }

  final int pipe;
  final Pointer<_Overlapped> ov = calloc<_Overlapped>();
  final Pointer<IntPtr> handles = calloc<IntPtr>(2);

  /// ByteOffset for NtReadFile/NtWriteFile: ignored by pipes, but passed the
  /// way kernel32 does (a zero LARGE_INTEGER).
  final Pointer<Int64> zeroOffset = calloc<Int64>();

  int get event => ov.ref.hEvent;

  /// Starts an operation with [start] (an Nt* call returning NTSTATUS) and
  /// waits for it. Returns (done, bytes), (closed|failed, NTSTATUS) or
  /// (timeout|stopped, 0). [timeoutMs] null waits forever.
  (PipeIoEnd, int) run(int Function(Pointer<_Overlapped> iosb) start,
      {required int? timeoutMs, int stopEvent = 0}) {
    ov.ref
      ..internal = 0
      ..internalHigh = 0
      ..offset = 0
      ..offsetHigh = 0;
    _resetEvent(event);
    final status = start(ov) & 0xFFFFFFFF;
    if (status != NtStatus.pending) {
      // Finished synchronously. On success the IO_STATUS_BLOCK holds the
      // byte count; on an error it may be untouched, the return is the truth.
      return _classify(status, ov.ref.internalHigh);
    }

    // Pending. The stop event comes first in the array, so it wins when both
    // are signalled.
    var n = 0;
    if (stopEvent != 0) handles[n++] = stopEvent;
    final ioIndex = n;
    handles[n++] = event;
    final ms = timeoutMs == null ? _infinite : (timeoutMs < 0 ? 0 : timeoutMs);
    final w = _waitForMultipleObjects(n, handles, 0, ms);
    if (w == _waitObject0 + ioIndex) {
      return _classify(ov.ref.internal & 0xFFFFFFFF, ov.ref.internalHigh);
    }
    // Timed out, stopped, or the wait failed: cancel, then wait for the
    // completion (STATUS_CANCELLED or a late result) so the block is idle.
    _cancelIoEx(pipe, ov);
    waitForEvent(event, timeoutMs: _infinite);
    if (w == _waitTimeout) return (PipeIoEnd.timeout, 0);
    if (stopEvent != 0 && w == _waitObject0) return (PipeIoEnd.stopped, 0);
    return (PipeIoEnd.failed, 0);
  }

  static (PipeIoEnd, int) _classify(int status, int information) {
    if (status == NtStatus.success) return (PipeIoEnd.done, information);
    if (_isClosedStatus(status)) return (PipeIoEnd.closed, status);
    return (PipeIoEnd.failed, status);
  }

  void dispose() {
    _closeHandle(event);
    _free();
  }

  void _free() {
    calloc.free(ov);
    calloc.free(handles);
    calloc.free(zeroOffset);
  }
}

// ---------------------------------------------------------------------------
// Server side

/// Creates one server instance of pipe [name]: duplex, overlapped, byte
/// mode, remote clients rejected, DACL from [pipeSddlForSid]([sid]). [first]
/// adds FILE_FLAG_FIRST_PIPE_INSTANCE, so it fails when the name already
/// exists (another instance, or another user's pipe); tell that case apart
/// with [pipeExists]. Throws [WinPipeException] on failure.
int createPipeServerInstance(String name,
    {required String sid, required bool first}) {
  return _withPipeSecurity(sid, (sa) {
    return using((arena) {
      final h = _createNamedPipeW(
        name.toNativeUtf16(allocator: arena),
        _pipeAccessDuplex |
            _fileFlagOverlapped |
            (first ? _fileFlagFirstPipeInstance : 0),
        _pipeTypeByte | _pipeReadmodeByte | _pipeWait | _pipeRejectRemoteClients,
        _pipeUnlimitedInstances,
        _chunk,
        _chunk,
        0,
        sa,
      );
      if (h == _invalidHandleValue) {
        throw WinPipeException('CreateNamedPipeW', _getLastError());
      }
      return h;
    });
  });
}

enum PipeConnect {
  connected,
  stopped,

  /// A client connected and left before we looked: call [disconnectPipe]
  /// and wait again on the same instance.
  clientGone,
}

/// Blocks until a client connects to [pipe] or [stopEvent] is signalled.
/// Throws [WinPipeException] on other failures.
PipeConnect waitForPipeClient(int pipe, {required int stopEvent}) {
  final io = _Io(pipe);
  try {
    final (end, status) = io.run(
        (iosb) => _ntFsControlFile(pipe, io.event, nullptr, nullptr, iosb,
            _fsctlPipeListen, nullptr, 0, nullptr, 0),
        timeoutMs: null,
        stopEvent: stopEvent);
    switch (end) {
      case PipeIoEnd.done:
        return PipeConnect.connected;
      case PipeIoEnd.stopped:
        return PipeConnect.stopped;
      default:
        // A client that connected between create and listen.
        if (status == NtStatus.pipeConnected) return PipeConnect.connected;
        // Connected and already closed its end.
        if (status == NtStatus.pipeClosing) return PipeConnect.clientGone;
        // Anything else: a client is attached iff it has a process id.
        if (_peerPid(pipe, _getNamedPipeClientProcessId) != null) {
          return PipeConnect.connected;
        }
        throw WinPipeException('NtFsControlFile(FSCTL_PIPE_LISTEN)', status);
    }
  } finally {
    io.dispose();
  }
}

void disconnectPipe(int pipe) => _disconnectNamedPipe(pipe);

int? _peerPid(int pipe, int Function(int pipe, Pointer<Uint32> pid) peerPid) {
  final pid = calloc<Uint32>();
  try {
    return peerPid(pipe, pid) == 0 ? null : pid.value;
  } finally {
    calloc.free(pid);
  }
}

/// Server side: the connected client process runs as our user.
bool pipeClientIsCurrentUser(int pipe) {
  final pid = _peerPid(pipe, _getNamedPipeClientProcessId);
  return pid != null && processRunsAsCurrentUser(pid);
}

/// Client side: the server process of [pipe] runs as our user.
bool pipeServerIsCurrentUser(int pipe) {
  final pid = _peerPid(pipe, _getNamedPipeServerProcessId);
  return pid != null && processRunsAsCurrentUser(pid);
}

/// Reads one request on a connected server [pipe]: [peerCheck] (the client
/// must run as our user) passes before anything is read, then a UTF-8 line
/// must arrive within [timeoutMs] and [maxBytes]. Null means drop the
/// client without a reply.
String? serveReadRequest(int pipe,
    {required int stopEvent,
    required int timeoutMs,
    required int maxBytes,
    bool Function(int pipe) peerCheck = pipeClientIsCurrentUser}) {
  if (!peerCheck(pipe)) return null;
  final r = readPipeLine(pipe,
      timeoutMs: timeoutMs, maxBytes: maxBytes, stopEvent: stopEvent);
  if (r.end != PipeIoEnd.newline) return null;
  try {
    return utf8.decode(r.bytes);
  } on FormatException {
    return null;
  }
}

/// Writes a response on a connected server [pipe], then waits (at most
/// [lingerMs]) for the client to close before the caller closes our end.
void serveWriteResponse(int pipe, List<int> bytes,
    {required int stopEvent, required int timeoutMs, int lingerMs = 2000}) {
  final w =
      writePipeAll(pipe, bytes, timeoutMs: timeoutMs, stopEvent: stopEvent);
  if (w != PipeIoEnd.done) return;
  readPipeLine(pipe,
      timeoutMs: lingerMs, maxBytes: _chunk, stopEvent: stopEvent);
}

// ---------------------------------------------------------------------------
// Client side

/// Opens the client end of pipe [name] (read/write, overlapped), or null when
/// CreateFileW fails (missing, busy or denied: use [pipeExists] and
/// [waitPipeAvailable] to tell them apart). SQOS identification level: a
/// server can identify us but never impersonate us.
int? tryOpenPipeClient(String name) => using((arena) {
      final h = _createFileW(
        name.toNativeUtf16(allocator: arena),
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        _fileFlagOverlapped | _securitySqosPresent | _securityIdentification,
        0,
      );
      return h == _invalidHandleValue ? null : h;
    });

/// Like [tryOpenPipeClient] but throws [WinPipeException] on failure.
int openPipeClient(String name) {
  final h = tryOpenPipeClient(name);
  if (h == null) throw WinPipeException('CreateFileW', _getLastError());
  return h;
}

/// Waits up to [timeoutMs] for a free instance of pipe [name]. The result is
/// advisory; opening decides.
bool waitPipeAvailable(String name, {required int timeoutMs}) =>
    using((arena) => _waitNamedPipeW(
            name.toNativeUtf16(allocator: arena), timeoutMs < 1 ? 1 : timeoutMs) !=
        0);

// ---------------------------------------------------------------------------
// Reading and writing (both ends)

/// A line read by [readPipeLine].
class PipeRead {
  const PipeRead(this.bytes, this.end, [this.status = 0]);

  /// The bytes before the newline (or everything read, if none came).
  final Uint8List bytes;
  final PipeIoEnd end;

  /// The NTSTATUS for [PipeIoEnd.closed] / [PipeIoEnd.failed].
  final int status;
}

/// Reads until a newline, close, more than [maxBytes] before the newline,
/// [timeoutMs] in total, or [stopEvent].
PipeRead readPipeLine(int pipe,
    {required int timeoutMs, required int maxBytes, int stopEvent = 0}) {
  final io = _Io(pipe);
  final buf = calloc<Uint8>(_chunk);
  final out = BytesBuilder(copy: false);
  final sw = Stopwatch()..start();
  try {
    while (true) {
      final left = timeoutMs - sw.elapsedMilliseconds;
      if (left <= 0) return PipeRead(out.takeBytes(), PipeIoEnd.timeout);
      final (end, v) = io.run(
          (iosb) => _ntReadFile(pipe, io.event, nullptr, nullptr, iosb, buf,
              _chunk, io.zeroOffset, nullptr),
          timeoutMs: left,
          stopEvent: stopEvent);
      switch (end) {
        case PipeIoEnd.done:
          final chunk = buf.asTypedList(v);
          final nl = chunk.indexOf(0x0A);
          final lineBytes = nl < 0 ? v : nl;
          if (out.length + lineBytes > maxBytes) {
            return PipeRead(Uint8List(0), PipeIoEnd.tooLong);
          }
          out.add(chunk.sublist(0, lineBytes)); // sublist copies
          if (nl >= 0) return PipeRead(out.takeBytes(), PipeIoEnd.newline);
        case PipeIoEnd.closed:
        case PipeIoEnd.failed:
          return PipeRead(out.takeBytes(), end, v);
        default:
          return PipeRead(out.takeBytes(), end);
      }
    }
  } finally {
    calloc.free(buf);
    io.dispose();
  }
}

/// Writes all of [data] within [timeoutMs]. [PipeIoEnd.done] on success,
/// otherwise closed / timeout / stopped / failed.
PipeIoEnd writePipeAll(int pipe, List<int> data,
    {required int timeoutMs, int stopEvent = 0}) {
  if (data.isEmpty) return PipeIoEnd.done;
  final io = _Io(pipe);
  final buf = calloc<Uint8>(data.length);
  buf.asTypedList(data.length).setAll(0, data);
  final sw = Stopwatch()..start();
  try {
    var off = 0;
    while (off < data.length) {
      final left = timeoutMs - sw.elapsedMilliseconds;
      if (left <= 0) return PipeIoEnd.timeout;
      final (end, v) = io.run(
          (iosb) => _ntWriteFile(pipe, io.event, nullptr, nullptr, iosb,
              buf + off, data.length - off, io.zeroOffset, nullptr),
          timeoutMs: left,
          stopEvent: stopEvent);
      if (end != PipeIoEnd.done) return end;
      off += v;
    }
    return PipeIoEnd.done;
  } finally {
    calloc.free(buf);
    io.dispose();
  }
}
