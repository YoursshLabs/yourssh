import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:path/path.dart' as p;

class LanShareService {
  HttpServer? _server;
  String? _sharedFilePath;

  Future<String?> share(String filePath, {int port = 8765}) async {
    await stop();
    _sharedFilePath = filePath;

    final handler = const Pipeline().addHandler(_handleRequest);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    final localIp = await NetworkInfo().getWifiIP();
    if (localIp == null) return null;
    return 'http://$localIp:$port/download/${Uri.encodeComponent(p.basename(filePath))}';
  }

  Response _handleRequest(Request request) {
    if (_sharedFilePath == null) return Response.notFound('No file shared');
    final file = File(_sharedFilePath!);
    if (!file.existsSync()) return Response.notFound('File not found');
    final filename = p.basename(_sharedFilePath!);
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': 'attachment; filename="$filename"',
        'Content-Length': file.lengthSync().toString(),
      },
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sharedFilePath = null;
  }

  bool get isRunning => _server != null;
}
