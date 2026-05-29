import 'package:flutter_test/flutter_test.dart';

String _tabLabel(String toolName, String input) {
  final raw = input.isEmpty ? toolName : '$toolName $input';
  return raw.length > 24 ? '${raw.substring(0, 21)}...' : raw;
}

void main() {
  group('_tabLabel', () {
    test('short label stays unchanged', () {
      expect(_tabLabel('Ping', '8.8.8.8'), 'Ping 8.8.8.8');
    });

    test('no input uses tool name only', () {
      expect(_tabLabel('Netstat', ''), 'Netstat');
    });

    test('long label truncated to 24 chars with ellipsis', () {
      final result = _tabLabel('Traceroute', 'very.long.hostname.example.com');
      expect(result.length, 24);
      expect(result.endsWith('...'), true);
    });

    test('exactly short enough — not truncated', () {
      expect(_tabLabel('Ping', 'ab'), 'Ping ab');
    });
  });
}
