import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/webview_result.dart';

void main() {
  group('decodeWebViewString', () {
    test('Android: decodes a JSON string literal', () {
      expect(
          decodeWebViewString(r'"line1\nline2 \"q\" é"', jsonEncoded: true),
          'line1\nline2 "q" é');
    });

    test('Android: empty document', () {
      expect(decodeWebViewString('""', jsonEncoded: true), '');
    });

    test('Android: non-string JSON literal is returned as-is', () {
      expect(decodeWebViewString('null', jsonEncoded: true), 'null');
      expect(decodeWebViewString('123', jsonEncoded: true), '123');
    });

    test('Android: malformed quoted text falls back to raw', () {
      expect(decodeWebViewString('"unterminated', jsonEncoded: true),
          '"unterminated');
    });

    test('other platforms: content is never decoded', () {
      expect(decodeWebViewString('"quoted"', jsonEncoded: false), '"quoted"');
    });

    test('accepts non-String results via toString', () {
      expect(decodeWebViewString(42, jsonEncoded: false), '42');
    });
  });
}
