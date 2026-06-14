import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/osc52_clipboard.dart';

String b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('Osc52Clipboard.parse', () {
    test('valid write decodes base64 text', () {
      final r = Osc52Clipboard.parse(['c', b64('hello world')]);
      expect(r, isA<Osc52Write>());
      expect((r as Osc52Write).text, 'hello world');
    });

    test('empty selection target still writes', () {
      final r = Osc52Clipboard.parse(['', b64('x')]);
      expect((r as Osc52Write).text, 'x');
    });

    test('read query (?) is ignored', () {
      expect(Osc52Clipboard.parse(['c', '?']), isA<Osc52Ignored>());
    });

    test('invalid base64 is ignored', () {
      expect(Osc52Clipboard.parse(['c', '!!!not base64!!!']),
          isA<Osc52Ignored>());
    });

    test('payload over the cap is ignored', () {
      final big = base64.encode(List<int>.filled(kOsc52MaxBytes + 1, 65));
      expect(Osc52Clipboard.parse(['c', big]), isA<Osc52Ignored>());
    });

    test('non-utf8 bytes decode without throwing', () {
      final raw = base64.encode([0xff, 0xfe, 0x41]);
      expect(Osc52Clipboard.parse(['c', raw]), isA<Osc52Write>());
    });

    test('malformed arg lists are ignored', () {
      expect(Osc52Clipboard.parse(<String>[]), isA<Osc52Ignored>());
      expect(Osc52Clipboard.parse(['c']), isA<Osc52Ignored>());
    });
  });
}
