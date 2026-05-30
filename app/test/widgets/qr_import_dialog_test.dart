import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> parseTransferCode(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final url = json['u'];
  final k = json['k'];
  if (url == null || k == null) throw const FormatException('missing fields');
  base64.decode(k as String);
  return {'url': url as String, 'key': k};
}

void main() {
  group('parseTransferCode', () {
    test('parses valid transfer code', () {
      final key = base64.encode(List.filled(32, 0));
      final input = jsonEncode({'u': 'http://192.168.1.5:12345/sync', 'k': key});
      final result = parseTransferCode(input);
      expect(result['url'], 'http://192.168.1.5:12345/sync');
      expect(result['key'], key);
    });

    test('throws FormatException on plain text', () {
      expect(() => parseTransferCode('not json'), throwsFormatException);
    });

    test('throws FormatException on JSON missing u field', () {
      final key = base64.encode(List.filled(32, 0));
      final input = jsonEncode({'k': key});
      expect(() => parseTransferCode(input), throwsFormatException);
    });

    test('throws FormatException on JSON missing k field', () {
      final input = jsonEncode({'u': 'http://192.168.1.5:12345/sync'});
      expect(() => parseTransferCode(input), throwsFormatException);
    });

    test('throws FormatException on invalid base64 key', () {
      final input = jsonEncode({'u': 'http://192.168.1.5:12345/sync', 'k': '!!!not-base64!!!'});
      expect(() => parseTransferCode(input), throwsFormatException);
    });

    test('throws FormatException on empty string', () {
      expect(() => parseTransferCode(''), throwsFormatException);
    });
  });

  group('transfer code clipboard text', () {
    test('qr json contains u and k fields', () {
      const url = 'http://192.168.1.10:54321/sync';
      final key = base64.encode(List.filled(32, 42));
      final qrData = jsonEncode({'u': url, 'k': key});
      final result = parseTransferCode(qrData);
      expect(result['url'], url);
      expect(result['key'], key);
    });
  });
}
