import 'dart:convert';
import 'dart:io';

class NetworkInterfaceInfo {
  final String name;
  final String address;

  const NetworkInterfaceInfo({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

class P2PSyncService {
  HttpServer? _server;

  Future<List<NetworkInterfaceInfo>> getLocalInterfaces() async {
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    return interfaces
        .expand((i) => i.addresses.map(
              (a) => NetworkInterfaceInfo(name: i.name, address: a.address),
            ))
        .where((i) => !i.address.startsWith('127.'))
        .toList();
  }

  Future<String> startServer({
    required String encryptedPayload,
    required String hostAddress,
  }) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final port = _server!.port;
    _handleRequests(encryptedPayload);
    return 'http://$hostAddress:$port/sync';
  }

  void _handleRequests(String encryptedPayload) {
    _server?.listen(
      (request) async {
        if (request.uri.path == '/sync' && request.method == 'GET') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.text
            ..write(encryptedPayload);
          await request.response.close();
          await stop();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      },
      onError: (_) {},
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String> fetchPayload(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 10));
    } finally {
      client.close();
    }
  }
}
