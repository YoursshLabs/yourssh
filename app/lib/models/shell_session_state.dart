import 'shell_command.dart';

class ShellSessionState {
  static const _maxCommands = 500;

  String? cwd;
  final List<ShellCommand> commands = [];

  ShellCommand? get _pending => commands.isEmpty ? null : commands.last;

  void setCwd(String path) => cwd = path;

  void onPromptStart(int promptLine) {
    commands.add(ShellCommand(promptLine: promptLine, cwd: cwd));
    if (commands.length > _maxCommands) commands.removeAt(0);
  }

  void onExec() => _pending?.startedAt = DateTime.now();

  void onFinished(int? exitCode) {
    final c = _pending;
    if (c == null) return;
    c.finishedAt = DateTime.now();
    c.exitCode = exitCode;
  }
}
