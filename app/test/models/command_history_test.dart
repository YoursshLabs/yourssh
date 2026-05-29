import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/command_history.dart';

void main() {
  group('CommandHistory', () {
    test('adds commands and retrieves in reverse order', () {
      final h = CommandHistory(maxSize: 3);
      h.add('ls');
      h.add('pwd');
      h.add('whoami');
      expect(h.entries, ['whoami', 'pwd', 'ls']);
    });

    test('evicts oldest when exceeding maxSize', () {
      final h = CommandHistory(maxSize: 2);
      h.add('ls');
      h.add('pwd');
      h.add('whoami');
      expect(h.entries, ['whoami', 'pwd']);
      expect(h.entries.length, 2);
    });

    test('deduplicates consecutive identical commands', () {
      final h = CommandHistory(maxSize: 10);
      h.add('ls');
      h.add('ls');
      expect(h.entries, ['ls']);
    });

    test('navigate returns null when empty', () {
      final h = CommandHistory(maxSize: 10);
      expect(h.navigateUp(), isNull);
      expect(h.navigateDown(), isNull);
    });

    test('navigateUp cycles through history, navigateDown returns toward empty', () {
      final h = CommandHistory(maxSize: 10);
      h.add('ls');
      h.add('pwd');
      expect(h.navigateUp(), 'pwd');
      expect(h.navigateUp(), 'ls');
      expect(h.navigateUp(), 'ls'); // clamps at oldest
      expect(h.navigateDown(), 'pwd');
      expect(h.navigateDown(), null); // past newest = empty input
    });

    test('resetCursor resets navigation position', () {
      final h = CommandHistory(maxSize: 10);
      h.add('ls');
      h.navigateUp();
      h.resetCursor();
      expect(h.navigateUp(), 'ls'); // back to top
    });

    test('toJson / fromJson roundtrip', () {
      final h = CommandHistory(maxSize: 10);
      h.add('ls');
      h.add('pwd');
      final h2 = CommandHistory.fromJson(h.toJson(), maxSize: 10);
      expect(h2.entries, h.entries);
    });
  });
}
