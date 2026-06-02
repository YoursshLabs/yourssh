import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/shell_session_state.dart';

void main() {
  test('A -> C -> D lifecycle on the latest command', () {
    final st = ShellSessionState();
    st.setCwd('/srv/app');
    st.onPromptStart(42);
    expect(st.commands.single.promptLine, 42);
    expect(st.commands.single.cwd, '/srv/app');
    expect(st.commands.single.isRunning, isFalse); // not yet exec'd
    st.onExec();
    expect(st.commands.single.isRunning, isTrue);
    st.onFinished(0);
    expect(st.commands.single.isRunning, isFalse);
    expect(st.commands.single.succeeded, isTrue);
    expect(st.commands.single.duration, isNotNull);
  });

  test('D finalizes previous, A opens next', () {
    final st = ShellSessionState()
      ..onPromptStart(1)
      ..onExec();
    st.onFinished(1); // cmd #1 fails
    st.onPromptStart(5); // next prompt
    expect(st.commands.length, 2);
    expect(st.commands[0].succeeded, isFalse);
    expect(st.commands[1].promptLine, 5);
  });

  test('finished/exec with no pending command is a no-op', () {
    final st = ShellSessionState();
    expect(() {
      st.onFinished(0);
      st.onExec();
    }, returnsNormally);
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
