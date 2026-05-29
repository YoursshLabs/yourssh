import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/web_tools/http_client.dart';

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

    test('handles CRLF line endings', () {
      expect(parseHeaders('Content-Type: application/json\r\nAccept: */*'),
          {'Content-Type': 'application/json', 'Accept': '*/*'});
    });
  });
}
