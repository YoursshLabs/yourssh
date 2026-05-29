import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/s3_bucket_entry.dart';

/// S3-compatible object storage client using AWS Signature V4.
class S3Service {
  final String endpoint;
  final String bucket;
  final String accessKey;
  final String secretKey;
  final String region;

  S3Service({
    required this.endpoint,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.region = 'us-east-1',
  });

  /// List objects under [prefix] (delimiter '/') — returns files + sub-prefixes.
  Future<List<S3BucketEntry>> listObjects(String prefix) async {
    final uri = _buildUri(queryParameters: {
      'list-type': '2',
      'delimiter': '/',
      if (prefix.isNotEmpty) 'prefix': prefix,
    });

    final response = await _signedGet(uri);
    if (response.statusCode != 200) {
      throw Exception('S3 list failed: ${response.statusCode} ${response.body}');
    }

    final doc = XmlDocument.parse(response.body);
    final entries = <S3BucketEntry>[];

    // Common prefixes (sub-folders)
    for (final cp in doc.findAllElements('CommonPrefixes')) {
      final pfx = cp.findElements('Prefix').first.innerText;
      entries.add(S3BucketEntry(key: pfx, isPrefix: true));
    }

    // Objects (files)
    for (final c in doc.findAllElements('Contents')) {
      final key = c.findElements('Key').first.innerText;
      final sizeText = c.findElements('Size').first.innerText;
      final lastMod = c.findElements('LastModified').firstOrNull?.innerText;
      final etagRaw = c.findElements('ETag').firstOrNull?.innerText;
      final etag = etagRaw?.replaceAll('"', '');

      if (key.endsWith('/')) continue; // Skip directory markers
      entries.add(S3BucketEntry(
        key: key,
        isPrefix: false,
        size: int.tryParse(sizeText) ?? 0,
        lastModified: lastMod != null ? DateTime.tryParse(lastMod) : null,
        etag: etag,
      ));
    }

    return entries;
  }

  /// Generate a pre-signed URL for downloading [key] (valid 1 hour).
  String presignedDownloadUrl(String key, {int expiresInSeconds = 3600}) {
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final credential = '$accessKey/$credentialScope';
    final encodedKey = Uri.encodeComponent(key);
    final host = _host;

    final canonicalQueryString = _buildCanonicalQuery({
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': credential,
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '$expiresInSeconds',
      'X-Amz-SignedHeaders': 'host',
    });

    final canonicalRequest = [
      'GET',
      '/$bucket/$encodedKey',
      canonicalQueryString,
      'host:$host\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _derivedSigningKey(secretKey, dateStamp, region);
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    final baseUrl = '${endpoint.trimRight()}/$bucket/$encodedKey';
    return '$baseUrl?$canonicalQueryString&X-Amz-Signature=$signature'; // ignore: prefer_interpolation_to_compose_strings
  }

  /// Upload [data] to [key]. Optional [onProgress] receives (bytesSent, totalBytes).
  Future<void> putObject(
    String key,
    Uint8List data, {
    String contentType = 'application/octet-stream',
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = _buildUri(path: '/$bucket/$key');
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(data).toString();
    final host = _host;

    final headers = {
      'content-type': contentType,
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-date': amzDate,
    };

    final canonicalRequest =
        _canonicalRequest('PUT', '/$bucket/$key', '', headers, bodyHash);
    final authHeader = _authHeader(canonicalRequest, headers, dateStamp, amzDate);
    headers['Authorization'] = authHeader;

    if (onProgress == null) {
      final response = await http.put(uri, headers: headers, body: data);
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('S3 upload failed: ${response.statusCode} ${response.body}');
      }
      return;
    }

    final client = http.Client();
    try {
      final request = http.StreamedRequest('PUT', uri);
      headers.forEach((k, v) => request.headers[k] = v);
      request.contentLength = data.length;

      final responseFuture = client.send(request);
      const chunkSize = 65536;
      var sent = 0;
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, data.length);
        request.sink.add(data.sublist(i, end));
        sent = end;
        onProgress(sent, data.length);
      }
      await request.sink.close();

      final streamed = await responseFuture;
      if (streamed.statusCode != 200 && streamed.statusCode != 204) {
        final body = await streamed.stream.bytesToString();
        throw Exception('S3 upload failed: ${streamed.statusCode} $body');
      }
    } finally {
      client.close();
    }
  }

  /// Delete object at [key].
  Future<void> deleteObject(String key) async {
    final uri = _buildUri(path: '/$bucket/$key');
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(<int>[]).toString();
    final host = _host;

    final headers = {
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-date': amzDate,
    };

    final canonicalRequest = _canonicalRequest('DELETE', '/$bucket/$key', '', headers, bodyHash);
    final authHeader = _authHeader(canonicalRequest, headers, dateStamp, amzDate);
    headers['Authorization'] = authHeader;

    final response = await http.delete(uri, headers: headers);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('S3 delete failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Copy object from [sourceKey] to [destKey] within the same bucket.
  Future<void> copyObject(String sourceKey, String destKey) async {
    final uri = _buildUri(path: '/$bucket/$destKey');
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(<int>[]).toString();
    final host = _host;
    final encodedSource = Uri.encodeComponent('/$bucket/$sourceKey');

    final headers = {
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-copy-source': encodedSource,
      'x-amz-date': amzDate,
      'x-amz-metadata-directive': 'COPY',
    };

    final canonicalRequest =
        _canonicalRequest('PUT', '/$bucket/$destKey', '', headers, bodyHash);
    final authHeader = _authHeader(canonicalRequest, headers, dateStamp, amzDate);
    headers['Authorization'] = authHeader;

    final response = await http.put(uri, headers: headers);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('S3 copy failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Download object at [key] and return its bytes.
  Future<Uint8List> downloadObject(String key) async {
    final uri = _buildUri(path: '/$bucket/$key');
    final response = await _signedGet(uri);
    if (response.statusCode != 200) {
      throw Exception('S3 download failed: ${response.statusCode} ${response.body}');
    }
    return response.bodyBytes;
  }

  // ── Signature V4 helpers ──

  String get _host {
    final uri = Uri.parse(endpoint);
    return uri.host + (uri.hasPort ? ':${uri.port}' : '');
  }

  Uri _buildUri({String? path, Map<String, String>? queryParameters}) {
    final base = Uri.parse(endpoint.trimRight());
    return base.replace(
      path: path ?? '/$bucket',
      queryParameters: queryParameters,
    );
  }

  Future<http.Response> _signedGet(Uri uri) async {
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(<int>[]).toString();
    final host = _host;

    final canonicalQuery = uri.query;
    final headers = {
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-date': amzDate,
    };

    final canonicalRequest = _canonicalRequest('GET', uri.path, canonicalQuery, headers, bodyHash);
    final authHeader = _authHeader(canonicalRequest, headers, dateStamp, amzDate);
    headers['Authorization'] = authHeader;

    return http.get(uri, headers: headers);
  }

  String _canonicalRequest(
    String method,
    String path,
    String canonicalQuery,
    Map<String, String> headers,
    String bodyHash,
  ) {
    final sortedHeaders = Map.fromEntries(
      headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final canonicalHeaders = sortedHeaders.entries
        .map((e) => '${e.key}:${e.value.trim()}')
        .join('\n');
    final canonicalHeadersBlock = '$canonicalHeaders\n';
    final signedHeaders = sortedHeaders.keys.join(';');
    final encodedPath = Uri.encodeFull(path).replaceAll('%2F', '/');

    return [method, encodedPath, canonicalQuery, canonicalHeadersBlock, signedHeaders, bodyHash].join('\n');
  }

  String _authHeader(
    String canonicalRequest,
    Map<String, String> headers,
    String dateStamp,
    String amzDate,
  ) {
    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _derivedSigningKey(secretKey, dateStamp, region);
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    final sortedHeaders = Map.fromEntries(
      headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final signedHeaders = sortedHeaders.keys.join(';');

    return 'AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
  }

  static List<int> _derivedSigningKey(String secret, String date, String region) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;

    final kSecret = utf8.encode('AWS4$secret');
    final kDate = hmac(kSecret, date);
    final kRegion = hmac(kDate, region);
    final kService = hmac(kRegion, 's3');
    return hmac(kService, 'aws4_request');
  }

  static String _dateStamp(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  static String _amzDate(DateTime dt) =>
      '${_dateStamp(dt)}T'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}Z';

  static String _buildCanonicalQuery(Map<String, String> params) {
    final sorted = params.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }
}
