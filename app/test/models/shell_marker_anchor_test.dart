import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';

/// Drives a real xterm [Terminal] the way SshService does: OSC 133;A marks the
/// prompt line, and markers must follow their lines (or vanish with them).
void main() {
  late Terminal term;
  late ShellIntegrationProvider shell;

  void wire() {
    term = Terminal(maxLines: 50);
    term.resize(40, 6);
    shell = ShellIntegrationProvider();
    term.onPrivateOSC = (code, args) => shell.handleOsc(
          's1',
          code,
          args,
          term.buffer.absoluteCursorY,
          anchorFactory: term.buffer.createAnchorFromCursor,
        );
  }

  List<int> rows() => [
        for (final c in shell.maybeStateFor('s1')?.liveCommands ?? const [])
          c.promptLine,
      ];

  bool lineBlank(int y) => term.buffer.lines[y].getText().trim().isEmpty;

  test('markers follow their lines when the screen scrolls', () {
    wire();
    term.write('\x1b]133;A\x07\$ one\r\n');
    term.write('\x1b]133;A\x07\$ two\r\n');
    for (var i = 0; i < 8; i++) {
      term.write('out $i\r\n');
    }
    expect(rows().length, 2);
    for (final y in rows()) {
      expect(term.buffer.lines[y].getText(), startsWith('\$ '));
    }
  });

  test('clear (ED 2 + ED 3) leaves no marker on an empty row', () {
    wire();
    term.write('\x1b]133;A\x07\$ ls\r\nfile\r\n');
    term.write('\x1b]133;A\x07\$ clear\r\n');
    term.write('\x1b[H\x1b[2J\x1b[3J');
    for (final y in rows()) {
      expect(lineBlank(y), isFalse, reason: 'marker on empty row $y');
    }
    expect(rows(), isEmpty);
    term.write('\x1b]133;A\x07\$ ');
    expect(rows(), [term.buffer.absoluteCursorY]);
  });

  test('scrollback trim drops markers whose lines were trimmed', () {
    wire();
    term.write('\x1b]133;A\x07\$ first\r\n');
    for (var i = 0; i < 80; i++) {
      term.write('line $i\r\n');
    }
    expect(rows(), isEmpty);
  });
}
