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

  /// Percent-encodes an object key per-segment so the `/` separators stay
  /// intact (S3 expects them un-encoded between path components).
  static String _encodeKey(String key) =>
      key.split('/').map(Uri.encodeComponent).join('/');

  String _keyPath(String key) => '/$bucket/${_encodeKey(key)}';

  /// Generate a pre-signed URL for downloading [key] (valid 1 hour).
  String presignedDownloadUrl(String key, {int expiresInSeconds = 3600}) {
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final credential = '$accessKey/$credentialScope';
    final path = _keyPath(key);
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
      path,
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

    return '${endpoint.trimRight()}$path?$canonicalQueryString&X-Amz-Signature=$signature';
  }

  /// Streamed upload of [data] (already in memory). Callers with large files
  /// should prefer [putObjectStream] which doesn't require buffering.
  Future<void> putObject(
    String key,
    Uint8List data, {
    String contentType = 'application/octet-stream',
    void Function(int sent, int total)? onProgress,
  }) {
    return putObjectStream(
      key,
      Stream<List<int>>.value(data),
      contentLength: data.length,
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  /// Streamed upload: reads from [body] in chunks without buffering the whole
  /// payload. Hash must be precomputed (S3 SigV4) or set to UNSIGNED-PAYLOAD;
  /// here we use UNSIGNED-PAYLOAD to avoid a first-pass file read.
  Future<void> putObjectStream(
    String key,
    Stream<List<int>> body, {
    required int contentLength,
    String contentType = 'application/octet-stream',
    void Function(int sent, int total)? onProgress,
  }) async {
    final path = _keyPath(key);
    final uri = _buildUri(path: path);
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    const bodyHash = 'UNSIGNED-PAYLOAD';
    final host = _host;

    final headers = {
      'content-type': contentType,
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-date': amzDate,
    };

    final canonicalRequest = _canonicalRequest('PUT', path, '', headers, bodyHash);
    headers['Authorization'] = _authHeader(canonicalRequest, headers, dateStamp, amzDate);

    final client = http.Client();
    try {
      final request = http.StreamedRequest('PUT', uri);
      headers.forEach((k, v) => request.headers[k] = v);
      request.contentLength = contentLength;

      final responseFuture = client.send(request);
      var sent = 0;
      // Pipe the source stream through, reporting progress per chunk.
      body.listen(
        (chunk) {
          request.sink.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent, contentLength);
        },
        onDone: request.sink.close,
        onError: (Object e, StackTrace st) => request.sink.addError(e, st),
        cancelOnError: true,
      );

      final streamed = await responseFuture;
      if (streamed.statusCode != 200 && streamed.statusCode != 204) {
        final errBody = await streamed.stream.bytesToString();
        throw Exception('S3 upload failed: ${streamed.statusCode} $errBody');
      }
    } finally {
      client.close();
    }
  }

  /// Delete object at [key].
  Future<void> deleteObject(String key) async {
    final path = _keyPath(key);
    final uri = _buildUri(path: path);
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

    final canonicalRequest = _canonicalRequest('DELETE', path, '', headers, bodyHash);
    headers['Authorization'] = _authHeader(canonicalRequest, headers, dateStamp, amzDate);

    final response = await http.delete(uri, headers: headers);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('S3 delete failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Copy object from [sourceKey] to [destKey] within the same bucket.
  Future<void> copyObject(String sourceKey, String destKey) async {
    final destPath = _keyPath(destKey);
    final uri = _buildUri(path: destPath);
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(<int>[]).toString();
    final host = _host;
    // S3 expects /<bucket>/<encoded-key>, with the slashes between segments
    // un-encoded. The previous Uri.encodeComponent encoded everything including
    // the slashes, breaking copies of any nested key.
    final copySource = '/$bucket/${_encodeKey(sourceKey)}';

    final headers = {
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-copy-source': copySource,
      'x-amz-date': amzDate,
      'x-amz-metadata-directive': 'COPY',
    };

    final canonicalRequest = _canonicalRequest('PUT', destPath, '', headers, bodyHash);
    headers['Authorization'] = _authHeader(canonicalRequest, headers, dateStamp, amzDate);

    final response = await http.put(uri, headers: headers);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('S3 copy failed: ${response.statusCode} ${response.body}');
    }
  }

  /// Download object at [key] and return its bytes.
  Future<Uint8List> downloadObject(String key) async {
    final uri = _buildUri(path: _keyPath(key));
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

    // SigV4 requires the canonical query to be sorted-by-key with proper
    // percent-encoding — `uri.query` keeps insertion order, which only
    // accidentally works for parameter sets that happen to already be sorted.
    final canonicalQuery = _buildCanonicalQuery(uri.queryParameters);
    final headers = {
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-date': amzDate,
    };

    final canonicalRequest = _canonicalRequest('GET', uri.path, canonicalQuery, headers, bodyHash);
    headers['Authorization'] = _authHeader(canonicalRequest, headers, dateStamp, amzDate);

    return http.get(uri, headers: headers);
  }

  /// Builds the canonical-request block. [path] is assumed to already be a
  /// valid URL path with slashes between segments — callers using object keys
  /// should pass `_keyPath(key)` rather than raw keys.
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

    return [method, path, canonicalQuery, canonicalHeadersBlock, signedHeaders, bodyHash].join('\n');
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
