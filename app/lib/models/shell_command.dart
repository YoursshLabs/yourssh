class ShellCommand {
  final int promptLine; // absolute buffer line of the prompt (for gutter/jump)
  final String? cwd;
  String? text; // best-effort, optional
  DateTime? startedAt; // set at exec (OSC 133;C)
  DateTime? finishedAt; // set at finished (OSC 133;D)
  int? exitCode;

  ShellCommand({required this.promptLine, this.cwd});

  bool get isRunning => startedAt != null && finishedAt == null;
  bool? get succeeded => exitCode == null ? null : exitCode == 0;
  Duration? get duration => (startedAt != null && finishedAt != null)
      ? finishedAt!.difference(startedAt!)
      : null;
}
