import 'shell_command.dart';

class ShellSessionState {
  static const _maxCommands = 500;

  String? cwd;
  final List<ShellCommand> commands = [];

  ShellCommand? get _pending => commands.isEmpty ? null : commands.last;

  void setCwd(String path) => cwd = path;

  void onPromptStart(int promptLine) {
    commands.add(ShellCommand(promptLine));
    if (commands.length > _maxCommands) commands.removeAt(0);
  }

  void onFinished(int? exitCode) => _pending?.exitCode = exitCode;
}
