import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

class SSHAgentUnavailableException implements Exception {
  final String message;
  const SSHAgentUnavailableException(this.message);
  @override
  String toString() => 'SSHAgentUnavailableException: $message';
}

class SystemAgentProxy {
  final _AgentSession _session;

  SystemAgentProxy._(this._session);

  static Future<SystemAgentProxy> connect() async {
    final sockPath = Platform.environment['SSH_AUTH_SOCK'];
    if (sockPath == null || sockPath.isEmpty) {
      throw const SSHAgentUnavailableException('SSH_AUTH_SOCK is not set');
    }
    return connectTo(sockPath);
  }

  static Future<SystemAgentProxy> connectTo(String socketPath) async {
    try {
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      return SystemAgentProxy._(_AgentSession(socket));
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

class _AgentSession {
  final Socket _socket;
  final _buffer = <int>[];
  Completer<void>? _dataWaiter;
  late final StreamSubscription<List<int>> _sub;

  _AgentSession(this._socket) {
    _sub = _socket.listen((chunk) {
      _buffer.addAll(chunk);
      _dataWaiter?.complete();
      _dataWaiter = null;
    });
  }

  void write(List<int> data) => _socket.add(data);

  Future<Uint8List> _readExact(int count) async {
    while (_buffer.length < count) {
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
    await _socket.close();
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
