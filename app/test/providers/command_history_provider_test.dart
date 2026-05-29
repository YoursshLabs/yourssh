import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/command_history_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recordCommand adds to session history', () async {
    final p = CommandHistoryProvider();
    await p.init();
    p.recordCommand('session-1', 'ls -la');
    expect(p.historyFor('session-1').entries.first, 'ls -la');
  });

  test('navigateUp returns most recent command', () async {
    final p = CommandHistoryProvider();
    await p.init();
    p.recordCommand('session-1', 'ls');
    p.recordCommand('session-1', 'pwd');
    expect(p.navigateUp('session-1'), 'pwd');
  });

  test('historyFor different sessions is independent', () async {
    final p = CommandHistoryProvider();
    await p.init();
    p.recordCommand('session-1', 'ls');
    p.recordCommand('session-2', 'pwd');
    expect(p.historyFor('session-1').entries, ['ls']);
    expect(p.historyFor('session-2').entries, ['pwd']);
  });

  test('suggestions returns entries matching prefix', () async {
    final p = CommandHistoryProvider();
    await p.init();
    p.recordCommand('session-1', 'git status');
    p.recordCommand('session-1', 'git log');
    p.recordCommand('session-1', 'ls');
    final suggestions = p.suggestions('session-1', 'git');
    expect(suggestions, containsAll(['git log', 'git status']));
    expect(suggestions, isNot(contains('ls')));
  });
}
