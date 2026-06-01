import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sync_code.dart';

void main() {
  group('SyncCode', () {
    test('generate produces 12 chars from the Crockford alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = SyncCode.generate();
        expect(code.length, 12);
        expect(code.split('').every(SyncCode.alphabet.contains), isTrue);
      }
    });

    test('generate is random across calls', () {
      expect(SyncCode.generate(), isNot(SyncCode.generate()));
    });

    test('normalize strips separators and uppercases', () {
      expect(SyncCode.normalize(' a-b c '), 'ABC');
    });

    test('normalize maps I/L to 1 and O to 0', () {
      expect(SyncCode.normalize('ILO'), '110');
    });

    test('isValid accepts a generated code and formatted/lowercase variants', () {
      final code = SyncCode.generate();
      expect(SyncCode.isValid(code), isTrue);
      expect(SyncCode.isValid(SyncCode.format(code)), isTrue);
      expect(SyncCode.isValid(code.toLowerCase()), isTrue);
    });

    test('isValid rejects wrong length and bad chars', () {
      expect(SyncCode.isValid('ABC'), isFalse);
      expect(SyncCode.isValid('AAAAAAAAAAAAA'), isFalse); // 13 chars
      expect(SyncCode.isValid(r'!@#$%^&*()_+='), isFalse);
    });

    test('format groups a 12-char code as XXXX-XXXX-XXXX', () {
      expect(SyncCode.format('ABCD2345EFGH'), 'ABCD-2345-EFGH');
    });
  });
}
