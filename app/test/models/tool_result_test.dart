import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/tool_result.dart';

void main() {
  test('ToolResult.success stores output', () {
    final r = ToolResult.success(output: '64 bytes from 8.8.8.8');
    expect(r.isSuccess, true);
    expect(r.output, '64 bytes from 8.8.8.8');
    expect(r.error, isNull);
  });

  test('ToolResult.failure stores error', () {
    final r = ToolResult.failure(error: 'Connection timed out');
    expect(r.isSuccess, false);
    expect(r.error, 'Connection timed out');
  });

  test('ToolResult.lines splits output into non-empty lines', () {
    final r = ToolResult.success(output: 'line1\n\nline2\nline3\n');
    expect(r.lines, ['line1', 'line2', 'line3']);
  });

  test('ToolResult.durationMs records elapsed time', () {
    final r = ToolResult.success(output: 'ok', durationMs: 142);
    expect(r.durationMs, 142);
  });
}
