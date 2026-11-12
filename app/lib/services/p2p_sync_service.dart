import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/discovered_host.dart';

class NetworkInterfaceInfo {
  final String name;
  final String address;

  const NetworkInterfaceInfo({required this.name, required this.address});

  // fix #10: delegate to SubnetInfo.interfaceDisplayName (single source of truth)
  String get displayName => SubnetInfo.interfaceDisplayName(name);

  @override
  String toString() => '$displayName — $address';
}

class P2PSyncService {
  HttpServer? _server;

  /// Invoked when the local HTTP server emits an error (e.g., socket closed
  /// mid-transfer). Without this, the receiver gets a vague "could not fetch"
  /// and the sender has no idea anything went wrong.
  void Function(Object error)? onServerError;

  @visibleForTesting
  InternetAddress? get boundAddress => _server?.address;

  /// Largest sync payload [fetchPayload] accepts.
  static const int maxPayloadBytes = 16 * 1024 * 1024;

  /// True for http URLs whose host is a loopback, link-local or private IP
  /// literal (or `localhost`) - a sync payload only ever comes from the LAN.
  static bool isAllowedSyncUrl(String url) {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on FormatException {
      return false;
    }
    if (uri.scheme != 'http' || uri.host.isEmpty) return false;
    if (uri.host == 'localhost') return true;
    final ip = InternetAddress.tryParse(uri.host);
    if (ip == null) return false;
    final b = ip.rawAddress;
    if (ip.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          b[0] == 127 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254);
    }
    return ip.isLoopback ||
        (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) || // fe80::/10
        (b[0] & 0xfe) == 0xfc; // fc00::/7
  }

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
    // Bind only to the interface the user picked, not every interface.
    _server = await HttpServer.bind(InternetAddress(hostAddress), 0);
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
      onError: (Object e, StackTrace st) {
        debugPrint('[P2PSyncService] HTTP server error: $e');
        onServerError?.call(e);
      },
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String> fetchPayload(String url) async {
    if (!isAllowedSyncUrl(url)) {
      throw Exception('Sync URL must be http on a local/private address');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      await response.timeout(const Duration(seconds: 10)).forEach((chunk) {
        bytes.add(chunk);
        if (bytes.length > maxPayloadBytes) {
          throw Exception('Sync payload exceeds $maxPayloadBytes bytes');
        }
      });
      return utf8.decode(bytes.takeBytes());
    } finally {
      client.close(force: true);
    }
  }
}
