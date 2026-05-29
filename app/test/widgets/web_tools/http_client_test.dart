import 'package:flutter_test/flutter_test.dart';

// Extracted pure helper — same logic as in HttpClientTool
Map<String, String> parseHeaders(String raw) {
  final result = <String, String>{};
  for (final line in raw.split('\n')) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}

void main() {
  group('parseHeaders', () {
    test('parses single header', () {
      expect(parseHeaders('Content-Type: application/json'),
          {'Content-Type': 'application/json'});
    });

    test('parses multiple headers', () {
      expect(parseHeaders('Accept: */*\nAuthorization: Bearer tok'),
          {'Accept': '*/*', 'Authorization': 'Bearer tok'});
    });

    test('ignores lines without colon', () {
      expect(parseHeaders('garbage\nX-Foo: bar'), {'X-Foo': 'bar'});
    });

    test('handles value with colons', () {
      expect(parseHeaders('X-Date: 2026-01-01T00:00:00Z'),
          {'X-Date': '2026-01-01T00:00:00Z'});
    });

    test('returns empty map for blank input', () {
      expect(parseHeaders(''), {});
    });
  });
}
