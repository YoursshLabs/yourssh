import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:path/path.dart' as p;

class LanShareService {
  static final _rng = Random.secure();

  HttpServer? _server;
  String? _sharedFilePath;
  String? _token;

  Future<String?> share(String filePath, {int port = 8765}) async {
    await stop();
    _sharedFilePath = filePath;
    _token = _generateToken();

    final handler = const Pipeline().addHandler(_handleRequest);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    final localIp = await NetworkInfo().getWifiIP();
    if (localIp == null) return null;
    final filenameSegment = Uri.encodeComponent(p.basename(filePath));
    return 'http://$localIp:$port/d/$_token/$filenameSegment';
  }

  Response _handleRequest(Request request) {
    final filePath = _sharedFilePath;
    final token = _token;
    if (filePath == null || token == null) {
      return Response.notFound('No file shared');
    }
    final segments = request.url.pathSegments;
    // Expect /d/<token>/<anything>. Anything else is a probe or a stale URL.
    if (segments.length < 2 || segments[0] != 'd' || segments[1] != token) {
      return Response.notFound('Not found');
    }
    final file = File(filePath);
    if (!file.existsSync()) return Response.notFound('File not found');
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': _contentDisposition(p.basename(filePath)),
        'Content-Length': file.lengthSync().toString(),
      },
    );
  }

  /// RFC 6266 `filename*=UTF-8''…` so embedded quotes or CRLF can't inject
  /// headers; falls back to a sanitized ASCII `filename=` for old clients.
  static String _contentDisposition(String filename) {
    final asciiFallback = filename
        .replaceAll(RegExp(r'[^\x20-\x7e]'), '_')
        .replaceAll('"', '')
        .replaceAll('\\', '')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
    final encoded = Uri.encodeComponent(filename);
    return 'attachment; filename="$asciiFallback"; filename*=UTF-8\'\'$encoded';
  }

  static String _generateToken() {
    final bytes = List<int>.generate(24, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sharedFilePath = null;
    _token = null;
  }

  bool get isRunning => _server != null;
}
