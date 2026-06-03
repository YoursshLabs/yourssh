import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/shell_session_state.dart';

void main() {
  test('A -> D lifecycle on the latest command', () {
    final st = ShellSessionState();
    st.setCwd('/srv/app');
    st.onPromptStart(42);
    expect(st.commands.single.promptLine, 42);
    expect(st.commands.single.succeeded, isNull); // pending until finished
    st.onFinished(0);
    expect(st.commands.single.succeeded, isTrue);
    expect(st.cwd, '/srv/app');
  });

  test('D finalizes previous, A opens next', () {
    final st = ShellSessionState()..onPromptStart(1);
    st.onFinished(1); // cmd #1 fails
    st.onPromptStart(5); // next prompt
    expect(st.commands.length, 2);
    expect(st.commands[0].succeeded, isFalse);
    expect(st.commands[1].promptLine, 5);
  });

  test('finished with no pending command is a no-op', () {
    final st = ShellSessionState();
    expect(() => st.onFinished(0), returnsNormally);
    expect(st.commands, isEmpty);
  });

  test('command list is capped', () {
    final st = ShellSessionState();
    for (var i = 0; i < 600; i++) {
      st.onPromptStart(i);
    }
    expect(st.commands.length, 500);
    expect(st.commands.first.promptLine, 100); // oldest dropped
  });
}
