import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/sync/transfer_code.dart';

void main() {
  test('parses a valid transfer code', () {
    final key = List<int>.generate(32, (i) => i);
    final raw = jsonEncode(
        {'u': 'http://192.168.1.5:8080/sync', 'k': base64.encode(key)});
    final parsed = parseTransferCode(raw);
    expect(parsed.url, 'http://192.168.1.5:8080/sync');
    expect(parsed.key, key);
  });

  test('throws on missing or malformed fields', () {
    expect(() => parseTransferCode('{"u":"http://x"}'), throwsFormatException);
    expect(() => parseTransferCode('not json'), throwsFormatException);
    expect(() => parseTransferCode('{"u":"","k":"AAAA"}'), throwsFormatException);
  });
}
