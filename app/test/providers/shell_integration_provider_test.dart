import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';

void main() {
  test('routes OSC events into per-session state + notifies', () {
    final p = ShellIntegrationProvider();
    var notifications = 0;
    p.addListener(() => notifications++);

    p.handleOsc('s1', '7', ['file://h/srv'], 0);
    p.handleOsc('s1', '133', ['A'], 7);
    p.handleOsc('s1', '133', ['C'], 7); // ignored — no exec tracking
    p.handleOsc('s1', '133', ['D', '0'], 7);

    expect(p.cwdFor('s1'), '/srv');
    final st = p.maybeStateFor('s1')!;
    expect(st.commands.single.promptLine, 7);
    expect(st.commands.single.succeeded, isTrue);
    expect(notifications, 3); // cwd + A + D (C ignored)
    expect(p.revisionFor('s1'), 3);
  });

  test('ignored OSC does not create state or notify', () {
    final p = ShellIntegrationProvider();
    var notifications = 0;
    p.addListener(() => notifications++);
    p.handleOsc('s1', '133', ['B'], 0); // B is a no-op
    expect(p.maybeStateFor('s1'), isNull);
    expect(notifications, 0);
  });

  test('clear removes state', () {
    final p = ShellIntegrationProvider()..handleOsc('s1', '7', ['file://h/x'], 0);
    p.clear('s1');
    expect(p.maybeStateFor('s1'), isNull);
  });
}
