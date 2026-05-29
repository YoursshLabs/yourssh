import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/web_tools/utility_tools.dart';

void main() {
  group('Base64', () {
    test('encodes hello world', () {
      expect(encodeBase64('hello world'), 'aGVsbG8gd29ybGQ=');
    });
    test('decodes back to original', () {
      expect(decodeBase64('aGVsbG8gd29ybGQ='), 'hello world');
    });
    test('invalid base64 returns error string', () {
      expect(decodeBase64('!!!'), 'Invalid Base64');
    });
  });

  group('URL encode/decode', () {
    test('encodes special chars', () {
      expect(encodeUrl('hello world & foo=bar'), 'hello%20world%20%26%20foo%3Dbar');
    });
    test('decodes back', () {
      expect(decodeUrl('hello%20world%20%26%20foo%3Dbar'), 'hello world & foo=bar');
    });
  });

  group('JSON', () {
    test('formats compact JSON', () {
      expect(formatJson('{"a":1,"b":2}'), '{\n  "a": 1,\n  "b": 2\n}');
    });
    test('invalid JSON returns error string', () {
      expect(formatJson('{bad}'), 'Invalid JSON');
    });
    test('minifies pretty JSON', () {
      expect(minifyJson('{\n  "a": 1,\n  "b": 2\n}'), '{"a":1,"b":2}');
    });
  });

  group('Hash', () {
    test('SHA-256 of empty string is known digest', () async {
      final hash = await Sha256().hash([]);
      final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });
  });
}
