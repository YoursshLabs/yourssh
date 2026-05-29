import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

String base64Encode(String input) => base64.encode(utf8.encode(input));
String base64Decode(String input) {
  try {
    return utf8.decode(base64.decode(input));
  } catch (_) {
    return 'Invalid Base64';
  }
}

String urlEncode(String input) => Uri.encodeComponent(input);
String urlDecode(String input) {
  try {
    return Uri.decodeComponent(input);
  } catch (_) {
    return 'Invalid URL encoding';
  }
}

String jsonFormat(String input) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(input));
  } catch (_) {
    return 'Invalid JSON';
  }
}

void main() {
  group('Base64', () {
    test('encodes hello world', () {
      expect(base64Encode('hello world'), 'aGVsbG8gd29ybGQ=');
    });
    test('decodes back to original', () {
      expect(base64Decode('aGVsbG8gd29ybGQ='), 'hello world');
    });
    test('invalid base64 returns error string', () {
      expect(base64Decode('!!!'), 'Invalid Base64');
    });
  });

  group('URL encode/decode', () {
    test('encodes special chars', () {
      expect(urlEncode('hello world & foo=bar'), 'hello%20world%20%26%20foo%3Dbar');
    });
    test('decodes back', () {
      expect(urlDecode('hello%20world%20%26%20foo%3Dbar'), 'hello world & foo=bar');
    });
  });

  group('JSON format', () {
    test('pretty-prints compact JSON', () {
      expect(jsonFormat('{"a":1,"b":2}'), '{\n  "a": 1,\n  "b": 2\n}');
    });
    test('invalid JSON returns error string', () {
      expect(jsonFormat('{bad}'), 'Invalid JSON');
    });
  });
}
