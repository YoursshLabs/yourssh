/// Hand-written Win32 bindings (kernel32 / advapi32) for the YourSSH CLI
/// named pipe, shared by the app's listener and the `yourssh` client.
///
/// Nothing loads a DLL until the first call, so importing this library is
/// safe on macOS and Linux.
///
/// Error codes: every call whose failure code we branch on returns at once
/// (the pipe handles are overlapped) and is bound `isLeaf: true`, so the VM
/// runs nothing between it and the `GetLastError` call that follows. Calls
/// that block (the waits, `WaitNamedPipeW`, `GetOverlappedResult` with
/// `bWait`) are not leaf calls: a blocking leaf call would hold up garbage
/// collection for the whole isolate group. Their results never depend on
/// `GetLastError`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Win32 error codes this library and its callers branch on.
abstract final class WinError {
  static const fileNotFound = 2; // ERROR_FILE_NOT_FOUND
  static const accessDenied = 5; // ERROR_ACCESS_DENIED
  static const lockViolation = 33; // ERROR_LOCK_VIOLATION
  static const handleEof = 38; // ERROR_HANDLE_EOF
  static const brokenPipe = 109; // ERROR_BROKEN_PIPE
  static const insufficientBuffer = 122; // ERROR_INSUFFICIENT_BUFFER
  static const pipeBusy = 231; // ERROR_PIPE_BUSY
  static const noData = 232; // ERROR_NO_DATA
  static const pipeNotConnected = 233; // ERROR_PIPE_NOT_CONNECTED
  static const pipeConnected = 535; // ERROR_PIPE_CONNECTED
  static const operationAborted = 995; // ERROR_OPERATION_ABORTED
  static const ioPending = 997; // ERROR_IO_PENDING
}

/// A Win32 call failed with [code] (`GetLastError`).
class WinPipeException implements Exception {
  const WinPipeException(this.op, this.code);
  final String op;
  final int code;
  @override
  String toString() => 'WinPipeException: $op failed (error $code)';
}

// ---------------------------------------------------------------------------
// Constants (winbase.h / winnt.h / fileapi.h / synchapi.h / sddl.h)

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

/// One I/O chunk; also the pipe's advisory in/out buffer size.
const int _chunk = 64 * 1024;

// ---------------------------------------------------------------------------
// Structs

/// `OVERLAPPED` (minwinbase.h): two ULONG_PTR, a union of two DWORDs with a
/// PVOID (8 bytes on every Windows ABI), then the event HANDLE. 32 bytes on
/// x64/arm64.
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
// Bindings. HANDLE = IntPtr, DWORD/ULONG = Uint32, BOOL = Int32.

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');

final _getLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
    isLeaf: true);

final _closeHandle =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'CloseHandle',
        isLeaf: true);

final _createNamedPipeW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Uint32, Uint32, Uint32,
        Uint32, Pointer<_SecurityAttributes>),
    int Function(Pointer<Utf16>, int, int, int, int, int, int,
        Pointer<_SecurityAttributes>)>('CreateNamedPipeW', isLeaf: true);

// Overlapped handle: returns at once.
final _connectNamedPipe = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>),
    int Function(int, Pointer<_Overlapped>)>('ConnectNamedPipe', isLeaf: true);

final _disconnectNamedPipe =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'DisconnectNamedPipe',
        isLeaf: true);

final _createFileW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<Utf16>, Uint32, Uint32,
        Pointer<_SecurityAttributes>, Uint32, Uint32, IntPtr),
    int Function(Pointer<Utf16>, int, int, Pointer<_SecurityAttributes>, int,
        int, int)>('CreateFileW', isLeaf: true);

// Blocks up to its timeout: not leaf.
final _waitNamedPipeW = _kernel32.lookupFunction<
    Int32 Function(Pointer<Utf16>, Uint32),
    int Function(Pointer<Utf16>, int)>('WaitNamedPipeW');

final _readFile = _kernel32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<_Overlapped>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<_Overlapped>)>('ReadFile', isLeaf: true);

final _writeFile = _kernel32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<_Overlapped>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<_Overlapped>)>('WriteFile', isLeaf: true);

// bWait = FALSE only (the operation has completed): returns at once.
final _getOverlappedResult = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>, Pointer<Uint32>, Int32),
    int Function(int, Pointer<_Overlapped>, Pointer<Uint32>,
        int)>('GetOverlappedResult', isLeaf: true);

// bWait = TRUE (after CancelIoEx): may block briefly, not leaf.
final _getOverlappedResultWait = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>, Pointer<Uint32>, Int32),
    int Function(
        int, Pointer<_Overlapped>, Pointer<Uint32>, int)>('GetOverlappedResult');

final _cancelIoEx = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<_Overlapped>),
    int Function(int, Pointer<_Overlapped>)>('CancelIoEx', isLeaf: true);

final _createEventW = _kernel32.lookupFunction<
    IntPtr Function(Pointer<_SecurityAttributes>, Int32, Int32, Pointer<Utf16>),
    int Function(Pointer<_SecurityAttributes>, int, int,
        Pointer<Utf16>)>('CreateEventW', isLeaf: true);

final _setEvent =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetEvent',
        isLeaf: true);

final _resetEvent =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'ResetEvent',
        isLeaf: true);

// Blocks: not leaf.
final _waitForMultipleObjects = _kernel32.lookupFunction<
    Uint32 Function(Uint32, Pointer<IntPtr>, Int32, Uint32),
    int Function(int, Pointer<IntPtr>, int, int)>('WaitForMultipleObjects');

final _getNamedPipeClientProcessId = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetNamedPipeClientProcessId',
    isLeaf: true);

final _getNamedPipeServerProcessId = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetNamedPipeServerProcessId',
    isLeaf: true);

final _getCurrentProcess =
    _kernel32.lookupFunction<IntPtr Function(), int Function()>(
        'GetCurrentProcess',
        isLeaf: true);

final _openProcess = _kernel32.lookupFunction<
    IntPtr Function(Uint32, Int32, Uint32),
    int Function(int, int, int)>('OpenProcess', isLeaf: true);

final _localFree = _kernel32.lookupFunction<IntPtr Function(Pointer<Void>),
    int Function(Pointer<Void>)>('LocalFree', isLeaf: true);

final _openProcessToken = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Pointer<IntPtr>),
    int Function(int, int, Pointer<IntPtr>)>('OpenProcessToken', isLeaf: true);

final _getTokenInformation = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32, Pointer<Uint32>),
    int Function(int, int, Pointer<Void>, int,
        Pointer<Uint32>)>('GetTokenInformation', isLeaf: true);

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

/// The SID in [token]'s TokenUser. The SID lives in an [arena] buffer.
Pointer<Void> _tokenUserSid(int token, Arena arena) {
  final needed = arena<Uint32>();
  var size = 256;
  for (var attempt = 0; attempt < 2; attempt++) {
    final buf = arena<Uint8>(size);
    if (_getTokenInformation(token, _tokenUserClass, buf.cast(), size, needed) !=
        0) {
      // TOKEN_USER { SID_AND_ATTRIBUTES User { PSID Sid; DWORD Attributes } }
      return buf.cast<Pointer<Void>>().value;
    }
    final err = _getLastError();
    if (err != WinError.insufficientBuffer || needed.value <= size) {
      throw WinPipeException('GetTokenInformation', err);
    }
    size = needed.value;
  }
  throw const WinPipeException(
      'GetTokenInformation', WinError.insufficientBuffer);
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

bool _isClosedCode(int code) =>
    code == WinError.brokenPipe ||
    code == WinError.pipeNotConnected ||
    code == WinError.noData ||
    code == WinError.handleEof;

/// One OVERLAPPED + event for a sequence of operations on [pipe]. Every
/// operation is waited for (or cancelled and waited for) before [run]
/// returns, so the structure is never freed under a pending I/O.
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
  final Pointer<Uint32> transferred = calloc<Uint32>();
  final Pointer<IntPtr> handles = calloc<IntPtr>(2);

  void _reset() {
    ov.ref
      ..internal = 0
      ..internalHigh = 0
      ..offset = 0
      ..offsetHigh = 0;
    _resetEvent(ov.ref.hEvent);
  }

  /// Starts an operation with [start] (ReadFile / WriteFile) and waits for
  /// it. Returns (done, bytes), (failed, error), (timeout|stopped, 0).
  (PipeIoEnd, int) run(int Function(Pointer<_Overlapped> ov) start,
      {required int? timeoutMs, int stopEvent = 0}) {
    _reset();
    if (start(ov) == 0) {
      final err = _getLastError();
      if (err != WinError.ioPending) return (PipeIoEnd.failed, err);
    }
    return wait(timeoutMs: timeoutMs, stopEvent: stopEvent);
  }

  /// Waits for the pending operation. The stop event comes first in the
  /// handle array so it wins when both are signalled.
  (PipeIoEnd, int) wait({required int? timeoutMs, int stopEvent = 0}) {
    var n = 0;
    if (stopEvent != 0) handles[n++] = stopEvent;
    final ioIndex = n;
    handles[n++] = ov.ref.hEvent;
    final ms = timeoutMs == null
        ? _infinite
        : (timeoutMs < 0 ? 0 : timeoutMs);
    final w = _waitForMultipleObjects(n, handles, 0, ms);
    if (w == _waitObject0 + ioIndex) {
      if (_getOverlappedResult(pipe, ov, transferred, 0) == 0) {
        return (PipeIoEnd.failed, _getLastError());
      }
      return (PipeIoEnd.done, transferred.value);
    }
    // Timed out, stopped or the wait failed: cancel, then wait for the
    // cancellation so the OVERLAPPED is idle again.
    _cancelIoEx(pipe, ov);
    _getOverlappedResultWait(pipe, ov, transferred, 1);
    if (w == _waitTimeout) return (PipeIoEnd.timeout, 0);
    if (stopEvent != 0 && w == _waitObject0) return (PipeIoEnd.stopped, 0);
    return (PipeIoEnd.failed, 0);
  }

  void dispose() {
    _closeHandle(ov.ref.hEvent);
    _free();
  }

  void _free() {
    calloc.free(ov);
    calloc.free(transferred);
    calloc.free(handles);
  }
}

// ---------------------------------------------------------------------------
// Server side

/// Creates one server instance of pipe [name]: duplex, overlapped, byte
/// mode, remote clients rejected, DACL from [pipeSddlForSid]([sid]). [first]
/// adds FILE_FLAG_FIRST_PIPE_INSTANCE: it then fails with ERROR_ACCESS_DENIED
/// when the name already exists (another instance or another user's pipe).
/// Throws [WinPipeException].
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
    io._reset();
    if (_connectNamedPipe(pipe, io.ov) != 0) return PipeConnect.connected;
    final err = _getLastError();
    if (err == WinError.pipeConnected) return PipeConnect.connected;
    if (err == WinError.noData) return PipeConnect.clientGone;
    if (err != WinError.ioPending) {
      throw WinPipeException('ConnectNamedPipe', err);
    }
    final (end, code) = io.wait(timeoutMs: null, stopEvent: stopEvent);
    switch (end) {
      case PipeIoEnd.done:
        return PipeConnect.connected;
      case PipeIoEnd.stopped:
        return PipeConnect.stopped;
      default:
        if (code == WinError.noData) return PipeConnect.clientGone;
        throw WinPipeException('ConnectNamedPipe', code);
    }
  } finally {
    io.dispose();
  }
}

void disconnectPipe(int pipe) => _disconnectNamedPipe(pipe);

bool _peerIsCurrentUser(
    int pipe, int Function(int pipe, Pointer<Uint32> pid) peerPid) {
  final pid = calloc<Uint32>();
  try {
    if (peerPid(pipe, pid) == 0) return false;
    return processRunsAsCurrentUser(pid.value);
  } finally {
    calloc.free(pid);
  }
}

/// Server side: the connected client process runs as our user.
bool pipeClientIsCurrentUser(int pipe) =>
    _peerIsCurrentUser(pipe, _getNamedPipeClientProcessId);

/// Client side: the server process of [pipe] runs as our user.
bool pipeServerIsCurrentUser(int pipe) =>
    _peerIsCurrentUser(pipe, _getNamedPipeServerProcessId);

/// Reads one request on a connected server [pipe]: the client must run as
/// our user, and a UTF-8 line must arrive within [timeoutMs] and
/// [maxBytes]. Null means drop the client without a reply.
String? serveReadRequest(int pipe,
    {required int stopEvent, required int timeoutMs, required int maxBytes}) {
  if (!pipeClientIsCurrentUser(pipe)) return null;
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

/// Opens the client end of pipe [name] (read/write, overlapped). SQOS
/// identification level: a server can identify us but never impersonate us.
/// Throws [WinPipeException] (ERROR_FILE_NOT_FOUND, ERROR_PIPE_BUSY,
/// ERROR_ACCESS_DENIED, ...).
int openPipeClient(String name) => using((arena) {
      final h = _createFileW(
        name.toNativeUtf16(allocator: arena),
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        _fileFlagOverlapped | _securitySqosPresent | _securityIdentification,
        0,
      );
      if (h == _invalidHandleValue) {
        throw WinPipeException('CreateFileW', _getLastError());
      }
      return h;
    });

/// Waits up to [timeoutMs] for a free instance of pipe [name]. The result is
/// advisory; [openPipeClient] decides.
bool waitPipeAvailable(String name, {required int timeoutMs}) =>
    using((arena) => _waitNamedPipeW(
            name.toNativeUtf16(allocator: arena), timeoutMs < 1 ? 1 : timeoutMs) !=
        0);

// ---------------------------------------------------------------------------
// Reading and writing (both ends)

/// A line read by [readPipeLine].
class PipeRead {
  const PipeRead(this.bytes, this.end, [this.error = 0]);

  /// The bytes before the newline (or everything read, if none came).
  final Uint8List bytes;
  final PipeIoEnd end;

  /// The Win32 error for [PipeIoEnd.failed].
  final int error;
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
      final (end, n) = io.run(
          (ov) => _readFile(pipe, buf, _chunk, nullptr, ov),
          timeoutMs: left,
          stopEvent: stopEvent);
      switch (end) {
        case PipeIoEnd.done:
          final chunk = buf.asTypedList(n);
          final nl = chunk.indexOf(0x0A);
          final lineBytes = nl < 0 ? n : nl;
          if (out.length + lineBytes > maxBytes) {
            return PipeRead(Uint8List(0), PipeIoEnd.tooLong);
          }
          out.add(Uint8List.fromList(chunk.sublist(0, lineBytes)));
          if (nl >= 0) return PipeRead(out.takeBytes(), PipeIoEnd.newline);
        case PipeIoEnd.failed:
          return _isClosedCode(n)
              ? PipeRead(out.takeBytes(), PipeIoEnd.closed)
              : PipeRead(out.takeBytes(), PipeIoEnd.failed, n);
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
      final (end, n) = io.run(
          (ov) => _writeFile(pipe, buf + off, data.length - off, nullptr, ov),
          timeoutMs: left,
          stopEvent: stopEvent);
      switch (end) {
        case PipeIoEnd.done:
          off += n;
        case PipeIoEnd.failed:
          return _isClosedCode(n) ? PipeIoEnd.closed : PipeIoEnd.failed;
        default:
          return end;
      }
    }
    return PipeIoEnd.done;
  } finally {
    calloc.free(buf);
    io.dispose();
  }
}
