import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

@visibleForTesting
Map<String, String> parseHeaders(String raw) {
  final result = <String, String>{};
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
  }
  return result;
}

class KvPair {
  String key;
  String value;
  bool enabled;
  KvPair(this.key, this.value, {this.enabled = true});
}

enum AuthType { none, bearer, basic, apiKey }

enum BodyType { none, raw, urlEncoded }

class HistoryItem {
  final String method;
  final String url;
  final int statusCode;
  final int durationMs;
  const HistoryItem({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
  });
}

class HttpResponse {
  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> headers;
  final String body;
  final bool isError;
  final int durationMs;
  final int sizeBytes;
  const HttpResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.body,
    this.isError = false,
    required this.durationMs,
    required this.sizeBytes,
  });
}

/// Conventional per-method colours (the REST-client palette).
Color methodColor(String m) => switch (m) {
  'GET' => const Color(0xFF61AFFE),
  'POST' => const Color(0xFF49CC90),
  'PUT' => const Color(0xFFFCA130),
  'PATCH' => const Color(0xFF50E3C2),
  'DELETE' => const Color(0xFFF93E3E),
  _ => YsColors.mutedForeground,
};

/// Status colour: 2xx ok, 3xx warn, 4xx+ and transport errors red.
Color statusColor(int code, {bool isError = false}) {
  if (isError) return YsColors.error;
  if (code >= 200 && code < 300) return YsColors.ok;
  if (code >= 400) return YsColors.error;
  if (code >= 300) return YsColors.warn;
  return YsColors.mutedForeground;
}
