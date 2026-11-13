import 'package:xterm/xterm.dart' show CellAnchor;
import 'shell_command.dart';

class ShellSessionState {
  static const _maxCommands = 500;

  String? cwd;
  final List<ShellCommand> commands = [];

  ShellCommand? get _pending => commands.isEmpty ? null : commands.last;

  void setCwd(String path) => cwd = path;

  /// Commands whose prompt line still exists in the terminal buffer.
  List<ShellCommand> get liveCommands =>
      [for (final c in commands) if (c.isLive) c];

  void onPromptStart(int promptLine, {CellAnchor? anchor}) {
    commands.removeWhere((c) => !c.isLive);
    commands.add(ShellCommand(promptLine, anchor: anchor));
    if (commands.length > _maxCommands) {
      commands.removeAt(0).anchor?.dispose();
    }
  }

  void onFinished(int? exitCode) => _pending?.exitCode = exitCode;
}
