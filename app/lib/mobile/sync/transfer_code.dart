import 'dart:convert';

/// Parses a P2P transfer code (the JSON encoded in the desktop's QR / export
/// string: `{"u": "<url>", "k": "<base64 key>"}`). Throws [FormatException]
/// on malformed input so the caller can show a clear "invalid code" error.
({String url, List<int> key}) parseTransferCode(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw.trim());
  } catch (_) {
    throw const FormatException('Not a valid transfer code');
  }
  if (decoded is! Map) throw const FormatException('Not a transfer code');
  final url = decoded['u'];
  final k = decoded['k'];
  if (url is! String || url.isEmpty || k is! String || k.isEmpty) {
    throw const FormatException('Transfer code is missing fields');
  }
  final List<int> key;
  try {
    key = base64.decode(k);
  } catch (_) {
    throw const FormatException('Transfer code key is invalid');
  }
  return (url: url, key: key);
}
