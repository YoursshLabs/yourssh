class ShellCommand {
  /// Absolute buffer line of this command's prompt (used by the gutter + jump).
  final int promptLine;

  /// Exit code, set when the command finishes (OSC 133;D). Null while pending.
  int? exitCode;

  ShellCommand(this.promptLine);

  /// null = pending/unknown · true = exit 0 · false = non-zero.
  bool? get succeeded => exitCode == null ? null : exitCode == 0;
}
