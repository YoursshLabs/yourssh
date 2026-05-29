class ToolResult {
  final bool isSuccess;
  final String? output;
  final String? error;
  final int durationMs;

  const ToolResult._({
    required this.isSuccess,
    this.output,
    this.error,
    this.durationMs = 0,
  });

  factory ToolResult.success({required String output, int durationMs = 0}) =>
      ToolResult._(isSuccess: true, output: output, durationMs: durationMs);

  factory ToolResult.failure({required String error}) =>
      ToolResult._(isSuccess: false, error: error);

  List<String> get lines =>
      (output ?? '').split('\n').where((l) => l.trim().isNotEmpty).toList();
}
