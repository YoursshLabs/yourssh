import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Win32 FFI — only executed on Windows at runtime
// ---------------------------------------------------------------------------

typedef _CreateFileWNative = IntPtr Function(
  Pointer<Utf16> lpFileName,
  Uint32 dwDesiredAccess,
  Uint32 dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  Uint32 dwCreationDisposition,
  Uint32 dwFlagsAndAttributes,
  IntPtr hTemplateFile,
);
typedef _CreateFileWDart = int Function(
  Pointer<Utf16> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  int hTemplateFile,
);

typedef _ReadFileNative = Int32 Function(
  IntPtr hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nNumberOfBytesToRead,
  Pointer<Uint32> lpNumberOfBytesRead,
  Pointer<Void> lpOverlapped,
);
typedef _ReadFileDart = int Function(
  int hFile,
  Pointer<Uint8> lpBuffer,
  int nNumberOfBytesToRead,
  Pointer<Uint32> lpNumberOfBytesRead,
  Pointer<Void> lpOverlapped,
);

typedef _WriteFileNative = Int32 Function(
  IntPtr hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nNumberOfBytesToWrite,
  Pointer<Uint32> lpNumberOfBytesWritten,
  Pointer<Void> lpOverlapped,
);
typedef _WriteFileDart = int Function(
  int hFile,
  Pointer<Uint8> lpBuffer,
  int nNumberOfBytesToWrite,
  Pointer<Uint32> lpNumberOfBytesWritten,
  Pointer<Void> lpOverlapped,
);

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

// Win32 constants
const int _kGenericRead = 0x80000000;
const int _kGenericWrite = 0x40000000;
const int _kFileShareNone = 0;
const int _kOpenExisting = 3;
const int _kFileAttributeNormal = 0x80;
// INVALID_HANDLE_VALUE = (HANDLE)(LONG_PTR)(-1)
const int _kInvalidHandle = -1;

class SSHAgentUnavailableException implements Exception {
  final String message;
  const SSHAgentUnavailableException(this.message);
  @override
  String toString() => 'SSHAgentUnavailableException: $message';
}

// ---------------------------------------------------------------------------
// Transport abstraction
// ---------------------------------------------------------------------------

abstract class _AgentTransport {
  void write(List<int> data);
  Stream<List<int>> get incoming;
  Future<void> close();
}

class _SocketTransport implements _AgentTransport {
  final Socket _socket;
  _SocketTransport(this._socket);

  @override
  void write(List<int> data) => _socket.add(data);

  @override
  Stream<List<int>> get incoming => _socket;

  @override
  Future<void> close() => _socket.close();
}

class _WindowsPipeTransport implements _AgentTransport {
  final int _handle;
  final _WriteFileDart _writeFn;
  final _CloseHandleDart _closeFn;
  final _controller = StreamController<List<int>>();
  late final Isolate _readIsolate;
  late final ReceivePort _receivePort;
  late final StreamSubscription<dynamic> _portSub;

  _WindowsPipeTransport._(this._handle, this._writeFn, this._closeFn);

  static Future<_WindowsPipeTransport> connect(String pipeName) async {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final createFile = kernel32
        .lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW');
    final writeFile = kernel32
        .lookupFunction<_WriteFileNative, _WriteFileDart>('WriteFile');
    final closeHandle = kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    final getLastError = kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

    final pipeNamePtr = pipeName.toNativeUtf16();
    final int handle;
    try {
      handle = createFile(
        pipeNamePtr,
        _kGenericRead | _kGenericWrite,
        _kFileShareNone,
        nullptr,
        _kOpenExisting,
        _kFileAttributeNormal,
        0,
      );
    } finally {
      calloc.free(pipeNamePtr);
    }

    if (handle == _kInvalidHandle) {
      final err = getLastError();
      throw SSHAgentUnavailableException(
        'Cannot open Windows SSH agent pipe (Win32 error $err). '
        'Ensure the OpenSSH Authentication Agent service is running.',
      );
    }

    final transport = _WindowsPipeTransport._(handle, writeFile, closeHandle);
    await transport._startReading();
    return transport;
  }

  Future<void> _startReading() async {
    _receivePort = ReceivePort();
    _portSub = _receivePort.listen((message) {
      if (message == null) {
        _controller.close();
      } else if (message is List<int>) {
        _controller.add(message);
      } else if (message is String) {
        _controller.addError(SSHAgentUnavailableException(message));
        _controller.close();
      }
    });
    _readIsolate = await Isolate.spawn(
      _readLoop,
      [_handle, _receivePort.sendPort],
      debugName: 'ssh_agent_pipe_reader',
    );
  }

  // Top-level-compatible static function required by Isolate.spawn.
  // Runs blocking ReadFile calls in a background isolate; sends chunks via SendPort.
  // Sends null on EOF, String message on error.
  static void _readLoop(List<dynamic> args) {
    final int handle = args[0] as int;
    final SendPort sendPort = args[1] as SendPort;

    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final readFile =
        kernel32.lookupFunction<_ReadFileNative, _ReadFileDart>('ReadFile');

    const bufSize = 4096;
    final buf = calloc<Uint8>(bufSize);
    final bytesRead = calloc<Uint32>();

    try {
      while (true) {
        final ok = readFile(handle, buf, bufSize, bytesRead, nullptr);
        if (ok == 0 || bytesRead.value == 0) {
          sendPort.send(null);
          break;
        }
        final chunk = List<int>.unmodifiable(buf.asTypedList(bytesRead.value));
        sendPort.send(chunk);
      }
    } finally {
      calloc.free(buf);
      calloc.free(bytesRead);
    }
  }

  @override
  void write(List<int> data) {
    final buf = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();
    try {
      for (var i = 0; i < data.length; i++) {
        buf[i] = data[i];
      }
      _writeFn(_handle, buf, data.length, written, nullptr);
    } finally {
      calloc.free(buf);
      calloc.free(written);
    }
  }

  @override
  Stream<List<int>> get incoming => _controller.stream;

  @override
  Future<void> close() async {
    _readIsolate.kill(priority: Isolate.immediate);
    await _portSub.cancel();
    _receivePort.close();
    await _controller.close();
    _closeFn(_handle);
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

class SystemAgentProxy {
  final _AgentSession _session;

  SystemAgentProxy._(this._session);

  static Future<SystemAgentProxy> connect() async {
    if (Platform.isWindows) return _connectWindows();
    final sockPath = Platform.environment['SSH_AUTH_SOCK'];
    if (sockPath == null || sockPath.isEmpty) {
      throw const SSHAgentUnavailableException('SSH_AUTH_SOCK is not set');
    }
    return connectTo(sockPath);
  }

  static Future<SystemAgentProxy> _connectWindows() async {
    // Prefer SSH_AUTH_SOCK when set — supports WSL agent forwarding and
    // third-party agents that expose a Unix-compatible socket on Windows.
    final sockPath = Platform.environment['SSH_AUTH_SOCK'];
    if (sockPath != null && sockPath.isNotEmpty) {
      try {
        return await connectTo(sockPath);
      } catch (_) {
        // Fall through to named pipe
      }
    }

    const pipePath = r'\\.\pipe\openssh-ssh-agent';
    try {
      final transport = await _WindowsPipeTransport.connect(pipePath);
      return SystemAgentProxy._(_AgentSession(transport));
    } on SSHAgentUnavailableException {
      rethrow;
    } catch (e) {
      throw SSHAgentUnavailableException(
        'No SSH agent found. Start the OpenSSH Authentication Agent service '
        'or set SSH_AUTH_SOCK. ($e)',
      );
    }
  }

  static Future<SystemAgentProxy> connectTo(String socketPath) async {
    try {
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      return SystemAgentProxy._(_AgentSession(_SocketTransport(socket)));
    } catch (e) {
      throw SSHAgentUnavailableException(
          'Cannot connect to SSH agent at $socketPath: $e');
    }
  }

  Future<List<SSHKeyPair>> getIdentities() async {
    final req = _AgentWriter()..writeUint8(11);
    _session.write(req.buildMessage());

    final body = await _session.readMessage();
    final reader = _AgentReader(body);
    final type = reader.readUint8();
    if (type != 12) {
      throw SSHAgentUnavailableException(
          'Expected IDENTITIES_ANSWER (12), got $type');
    }

    final nkeys = reader.readUint32();
    final pairs = <SSHKeyPair>[];
    for (var i = 0; i < nkeys; i++) {
      final keyBlob = reader.readBytes();
      reader.readBytes(); // comment — ignored
      pairs.add(_AgentKeyPair(keyBlob, _session));
    }
    return pairs;
  }

  Future<void> close() => _session.close();
}

// ---------------------------------------------------------------------------
// Wire protocol helpers
// ---------------------------------------------------------------------------

class _AgentWriter {
  final _buf = BytesBuilder();

  void writeUint8(int v) => _buf.addByte(v);

  void writeUint32(int v) {
    final b = Uint8List(4);
    ByteData.view(b.buffer).setUint32(0, v, Endian.big);
    _buf.add(b);
  }

  void writeBytes(List<int> data) {
    writeUint32(data.length);
    _buf.add(data);
  }

  Uint8List buildMessage() {
    final body = _buf.toBytes();
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
    return Uint8List.fromList([...header, ...body]);
  }
}

class _AgentReader {
  final Uint8List _data;
  int _offset = 0;

  _AgentReader(this._data);

  int readUint8() => _data[_offset++];

  int readUint32() {
    final v = ByteData.view(
      _data.buffer, _data.offsetInBytes + _offset, 4,
    ).getUint32(0, Endian.big);
    _offset += 4;
    return v;
  }

  Uint8List readBytes() {
    final len = readUint32();
    final result = _data.sublist(_offset, _offset + len);
    _offset += len;
    return result;
  }
}

/// Buffers incoming transport data and supports sequential async message reads.
///
/// Not thread-safe: callers must not issue concurrent [readMessage] calls.
/// The SSH agent protocol is inherently serial (request/response), so this is
/// satisfied as long as [_AgentKeyPair.signAsync] calls are not overlapped.
class _AgentSession {
  final _AgentTransport _transport;
  final _buffer = <int>[];
  Completer<void>? _dataWaiter;
  late final StreamSubscription<List<int>> _sub;
  Object? _closeError;

  _AgentSession(this._transport) {
    _sub = _transport.incoming.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _dataWaiter?.complete();
        _dataWaiter = null;
      },
      onError: (Object e, StackTrace st) {
        _closeError = e;
        _dataWaiter?.completeError(e, st);
        _dataWaiter = null;
      },
      onDone: () {
        _closeError ??= const SSHAgentUnavailableException(
            'Agent socket closed unexpectedly');
        _dataWaiter?.completeError(_closeError!);
        _dataWaiter = null;
      },
    );
  }

  void write(List<int> data) => _transport.write(data);

  Future<Uint8List> _readExact(int count) async {
    while (_buffer.length < count) {
      if (_closeError != null) throw _closeError!;
      _dataWaiter = Completer();
      await _dataWaiter!.future;
    }
    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }

  Future<Uint8List> readMessage() async {
    final header = await _readExact(4);
    final len = ByteData.view(header.buffer).getUint32(0, Endian.big);
    return _readExact(len);
  }

  Future<void> close() async {
    await _sub.cancel();
    await _transport.close();
  }
}

class _AgentKeyPair implements SSHKeyPair {
  final Uint8List _keyBlob;
  final _AgentSession _session;

  _AgentKeyPair(this._keyBlob, this._session);

  @override
  String get name => type;

  @override
  String get type {
    if (_keyBlob.length < 4) throw FormatException('Key blob too short');
    final nameLen = ByteData.view(
      _keyBlob.buffer, _keyBlob.offsetInBytes, 4,
    ).getUint32(0, Endian.big);
    return utf8.decode(_keyBlob.sublist(4, 4 + nameLen));
  }

  @override
  SSHHostKey toPublicKey() => _RawBlobHostKey(_keyBlob);

  @override
  SSHSignature sign(Uint8List data) {
    throw UnsupportedError(
        '_AgentKeyPair requires signAsync() — use the patched dartssh2 fork');
  }

  @override
  Future<SSHSignature> signAsync(Uint8List data) async {
    final req = _AgentWriter()
      ..writeUint8(13)
      ..writeBytes(_keyBlob)
      ..writeBytes(data)
      ..writeUint32(0);
    _session.write(req.buildMessage());

    final body = await _session.readMessage();
    final reader = _AgentReader(body);
    final type = reader.readUint8();
    if (type != 14) {
      if (type == 5) throw Exception('SSH agent refused to sign');
      throw Exception('Unexpected agent response: $type');
    }
    final sig = reader.readBytes();
    return _RawSignature(sig);
  }

  @override
  String toPem() =>
      throw UnsupportedError('Agent keys cannot be serialized to PEM');
}

class _RawBlobHostKey implements SSHHostKey {
  final Uint8List _bytes;
  const _RawBlobHostKey(this._bytes);
  @override
  Uint8List encode() => _bytes;
}

class _RawSignature implements SSHSignature {
  final Uint8List _bytes;
  const _RawSignature(this._bytes);
  @override
  Uint8List encode() => _bytes;
}
