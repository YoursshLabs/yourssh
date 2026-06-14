import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host.osc52Clipboard', () {
    test('defaults to false', () {
      final h = Host(label: 'a', host: 'h', username: 'u');
      expect(h.osc52Clipboard, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final h = Host(label: 'a', host: 'h', username: 'u', osc52Clipboard: true);
      final back = Host.fromJson(h.toJson());
      expect(back.osc52Clipboard, isTrue);
    });

    test('absent key in json defaults to false', () {
      final json = Host(label: 'a', host: 'h', username: 'u').toJson()
        ..remove('osc52Clipboard');
      expect(Host.fromJson(json).osc52Clipboard, isFalse);
    });

    test('copyWith overrides the field', () {
      final h = Host(label: 'a', host: 'h', username: 'u');
      expect(h.copyWith(osc52Clipboard: true).osc52Clipboard, isTrue);
      expect(h.copyWith().osc52Clipboard, isFalse);
    });
  });
}
