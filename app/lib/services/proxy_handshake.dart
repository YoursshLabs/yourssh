import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Raised for any proxy handshake failure (refusal, auth, malformed reply,
/// early close).
class ProxyException implements Exception {
  final String message;
  const ProxyException(this.message);
  @override
  String toString() => 'ProxyException: $message';
}

/// Upper bound for buffered proxy response headers.
const int kMaxProxyHeaderBytes = 64 * 1024;

/// Buffered byte reader over a socket stream. Serves [readExactly]/[readUntil]
/// during the handshake; afterwards [takeLeftover] returns the buffered tail
/// and [release] hands the live remainder out as a stream. Single pending read
/// at a time (handshakes are sequential).
class ByteReader {
  ByteReader(Stream<Uint8List> stream) {
    _sub = stream.listen(_onData, onError: _onError, onDone: _onDone);
  }

  late final StreamSubscription<Uint8List> _sub;
  final List<int> _buf = [];
  bool _done = false;
  Object? _error;
  void Function()? _wake;
  StreamController<Uint8List>? _out;

  void _onData(Uint8List chunk) {
    if (_out != null) {
      _out!.add(chunk);
      return;
    }
    _buf.addAll(chunk);
    _wake?.call();
  }

  void _onError(Object e, StackTrace st) {
    if (_out != null) {
      _out!.addError(e, st);
      return;
    }
    _error = e;
    _wake?.call();
  }

  void _onDone() {
    if (_out != null) {
      _out!.close();
      return;
    }
    _done = true;
    _wake?.call();
  }

  Future<Uint8List> readExactly(int n) {
    final completer = Completer<Uint8List>();
    void attempt() {
      if (completer.isCompleted) return;
      if (_error != null) {
        _wake = null;
        completer.completeError(_error!);
      } else if (_buf.length >= n) {
        final out = Uint8List.fromList(_buf.sublist(0, n));
        _buf.removeRange(0, n);
        _wake = null;
        completer.complete(out);
      } else if (_done) {
        _wake = null;
        completer.completeError(
            const ProxyException('proxy closed connection during handshake'));
      }
    }

    _wake = attempt;
    attempt();
    return completer.future;
  }

  Future<Uint8List> readUntil(List<int> delimiter) {
    final completer = Completer<Uint8List>();
    void attempt() {
      if (completer.isCompleted) return;
      if (_error != null) {
        _wake = null;
        completer.completeError(_error!);
        return;
      }
      final idx = _indexOf(_buf, delimiter);
      if (idx >= 0) {
        final end = idx + delimiter.length;
        final out = Uint8List.fromList(_buf.sublist(0, end));
        _buf.removeRange(0, end);
        _wake = null;
        completer.complete(out);
      } else if (_buf.length > kMaxProxyHeaderBytes) {
        _wake = null;
        completer.completeError(
            const ProxyException('proxy response headers too large'));
      } else if (_done) {
        _wake = null;
        completer.completeError(
            const ProxyException('proxy closed connection during handshake'));
      }
    }

    _wake = attempt;
    attempt();
    return completer.future;
  }

  /// The bytes buffered but not consumed by the handshake.
  Uint8List takeLeftover() {
    final out = Uint8List.fromList(_buf);
    _buf.clear();
    return out;
  }

  /// Hands the live remainder of the stream out. Call once, after the
  /// handshake. The buffer must already be drained via [takeLeftover].
  Stream<Uint8List> release() {
    final out = StreamController<Uint8List>();
    _out = out;
    out.onCancel = () => _sub.cancel();
    if (_done) {
      out.close();
    } else if (_error != null) {
      out.addError(_error!);
    }
    return out.stream;
  }

  Future<void> destroy() => _sub.cancel();

  static int _indexOf(List<int> hay, List<int> needle) {
    for (var i = 0; i + needle.length <= hay.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

/// HTTP CONNECT handshake. Writes the request (optional Basic auth), reads
/// response headers up to `\r\n\r\n`, requires a 200 status. Returns the
/// bytes already read past the header terminator.
Future<Uint8List> httpConnectHandshake(
  ByteReader reader,
  StreamSink<List<int>> sink, {
  required String targetHost,
  required int targetPort,
  String? username,
  String? password,
}) async {
  if (targetHost.contains('\r') || targetHost.contains('\n')) {
    throw const ProxyException('invalid target host');
  }
  final req = StringBuffer()
    ..write('CONNECT $targetHost:$targetPort HTTP/1.1\r\n')
    ..write('Host: $targetHost:$targetPort\r\n');
  if (username != null && username.isNotEmpty) {
    final cred = base64.encode(utf8.encode('$username:${password ?? ''}'));
    req.write('Proxy-Authorization: Basic $cred\r\n');
  }
  req.write('\r\n');
  sink.add(utf8.encode(req.toString()));

  final header = await reader.readUntil(const [13, 10, 13, 10]); // \r\n\r\n
  final statusLine = ascii.decode(header, allowInvalid: true).split('\r\n').first;
  final parts = statusLine.split(' ');
  if (parts.length < 2 || parts[1] != '200') {
    throw ProxyException('HTTP proxy refused: $statusLine');
  }
  return reader.takeLeftover();
}

/// SOCKS5 handshake: greeting (no-auth + optional user/pass), optional RFC 1929
/// auth, then a CONNECT request with the target as a domain address (ATYP 0x03 →
/// remote DNS). Returns any over-read tail.
Future<Uint8List> socks5Handshake(
  ByteReader reader,
  StreamSink<List<int>> sink, {
  required String targetHost,
  required int targetPort,
  String? username,
  String? password,
}) async {
  final hasAuth = username != null && username.isNotEmpty;
  // RFC 1929 length fields are one byte: reject instead of silently truncating.
  if (hasAuth &&
      (utf8.encode(username).length > 255 ||
          utf8.encode(password ?? '').length > 255)) {
    throw const ProxyException(
        'SOCKS5 username/password must be at most 255 bytes');
  }
  final methods = hasAuth ? [0x00, 0x02] : [0x00];
  sink.add(Uint8List.fromList([0x05, methods.length, ...methods]));

  final sel = await reader.readExactly(2);
  if (sel[0] != 0x05) throw const ProxyException('not a SOCKS5 proxy');
  final method = sel[1];
  if (method == 0xFF) {
    throw const ProxyException('SOCKS5 proxy rejected all auth methods');
  }
  if (method == 0x02) {
    if (!hasAuth) {
      throw const ProxyException('SOCKS5 proxy requires username/password');
    }
    final u = utf8.encode(username);
    final p = utf8.encode(password ?? '');
    sink.add(Uint8List.fromList([0x01, u.length, ...u, p.length, ...p]));
    final authResp = await reader.readExactly(2);
    if (authResp[1] != 0x00) {
      throw const ProxyException('SOCKS5 authentication failed');
    }
  } else if (method != 0x00) {
    throw ProxyException('SOCKS5 proxy selected unsupported method $method');
  }

  final hostBytes = utf8.encode(targetHost);
  if (hostBytes.length > 255) {
    throw const ProxyException('hostname too long for SOCKS5');
  }
  sink.add(Uint8List.fromList([
    0x05, 0x01, 0x00, 0x03, hostBytes.length, ...hostBytes,
    (targetPort >> 8) & 0xff, targetPort & 0xff,
  ]));

  final head = await reader.readExactly(4); // VER, REP, RSV, ATYP
  if (head[1] != 0x00) throw ProxyException(_socksReplyMessage(head[1]));
  final atyp = head[3];
  int addrLen;
  if (atyp == 0x01) {
    addrLen = 4;
  } else if (atyp == 0x04) {
    addrLen = 16;
  } else if (atyp == 0x03) {
    addrLen = (await reader.readExactly(1))[0];
  } else {
    throw ProxyException('SOCKS5 unsupported address type $atyp');
  }
  await reader.readExactly(addrLen + 2); // bound address + port
  return reader.takeLeftover();
}

String _socksReplyMessage(int rep) {
  switch (rep) {
    case 0x01:
      return 'SOCKS5 general failure';
    case 0x02:
      return 'SOCKS5 connection not allowed by ruleset';
    case 0x03:
      return 'SOCKS5 network unreachable';
    case 0x04:
      return 'SOCKS5 host unreachable';
    case 0x05:
      return 'SOCKS5 connection refused';
    case 0x06:
      return 'SOCKS5 TTL expired';
    case 0x07:
      return 'SOCKS5 command not supported';
    case 0x08:
      return 'SOCKS5 address type not supported';
    default:
      return 'SOCKS5 failed (code $rep)';
  }
}
