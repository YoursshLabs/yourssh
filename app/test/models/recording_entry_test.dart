import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/recording_entry.dart';

void main() {
  // fromPath splits on Platform.pathSeparator (paths come from dir.list()),
  // so the fixtures must use the platform separator to be portable.
  final sep = Platform.pathSeparator;

  test('fromFile parses hostTitle and recordedAt from path', () {
    final path = [
      '', 'tmp', 'Recordings', 'ubuntu@prod',
      'session_2026-05-30_09-15-30.cast',
    ].join(sep);
    final entry = RecordingEntry.fromPath(path);
    expect(entry.hostTitle, 'ubuntu@prod');
    expect(entry.recordedAt, DateTime(2026, 5, 30, 9, 15, 30));
    expect(entry.filePath, path);
  });

  test('fromPath handles malformed filename gracefully', () {
    final entry = RecordingEntry.fromPath(
        ['', 'tmp', 'Recordings', 'ubuntu@prod', 'unknown.cast'].join(sep));
    expect(entry.hostTitle, 'ubuntu@prod');
    expect(entry.recordedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
