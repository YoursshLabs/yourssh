import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/widgets/host_avatar.dart';

void main() {
  group('hostInitials', () {
    test('two words → first letter of each, uppercased', () {
      expect(hostInitials('production web'), 'PW');
    });
    test('single word → first two letters', () {
      expect(hostInitials('staging'), 'ST');
    });
    test('single letter → one letter', () {
      expect(hostInitials('x'), 'X');
    });
    test('blank → empty', () {
      expect(hostInitials('   '), '');
    });
    test('skips non-letter leading tokens', () {
      expect(hostInitials('10.0.0.5'), '1');
    });
  });
}
