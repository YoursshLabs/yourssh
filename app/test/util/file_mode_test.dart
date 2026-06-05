// app/test/util/file_mode_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/file_mode.dart';

void main() {
  group('modeToOctal', () {
    test('formats common permission bits', () {
      expect(modeToOctal(0x1ED), '755'); // 0o755
      expect(modeToOctal(0x1A4), '644'); // 0o644
      expect(modeToOctal(0), '000');
    });

    test('masks file-type bits and keeps special bits', () {
      // Regular file (0o100644) -> '644'
      expect(modeToOctal(0x81A4), '644');
      // setuid + 0o755 (0o4755)
      expect(modeToOctal(0x9ED), '4755');
    });
  });

  group('parseOctal', () {
    test('parses 3- and 4-digit octal strings', () {
      expect(parseOctal('755'), 0x1ED);
      expect(parseOctal('0644'), 0x1A4);
      expect(parseOctal('4755'), 0x9ED);
    });

    test('rejects invalid input', () {
      expect(parseOctal(''), isNull);
      expect(parseOctal('78'), isNull); // 8 is not an octal digit
      expect(parseOctal('77777'), isNull); // too long
      expect(parseOctal('abc'), isNull);
    });

    test('rejects 1- and 2-digit strings (partially typed modes)', () {
      // '64' is 0o064, not a truncated 0o644 — applying it would silently
      // strip owner permissions, so short strings never parse.
      expect(parseOctal('7'), isNull);
      expect(parseOctal('64'), isNull);
    });
  });
}
