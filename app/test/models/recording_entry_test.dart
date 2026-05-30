import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/recording_entry.dart';

void main() {
  test('fromFile parses hostTitle and recordedAt from path', () {
    final file = File('/tmp/Recordings/ubuntu@prod/session_2026-05-30_09-15-30.cast');
    final entry = RecordingEntry.fromPath(file.path);
    expect(entry.hostTitle, 'ubuntu@prod');
    expect(entry.recordedAt, DateTime(2026, 5, 30, 9, 15, 30));
    expect(entry.filePath, file.path);
  });

  test('fromPath handles malformed filename gracefully', () {
    final entry = RecordingEntry.fromPath('/tmp/Recordings/ubuntu@prod/unknown.cast');
    expect(entry.hostTitle, 'ubuntu@prod');
    expect(entry.recordedAt, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
