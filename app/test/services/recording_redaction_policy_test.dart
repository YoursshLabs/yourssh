import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/recording_redaction_policy.dart';

void main() {
  Host h({required bool redaction}) => Host(
      label: 'x', host: 'y', username: 'z', recordingRedaction: redaction);

  test('global on + host on = redact', () {
    expect(
        effectiveRecordingRedaction(
            globalEnabled: true, host: h(redaction: true)),
        isTrue);
  });

  test('global on + host opted out = no redaction', () {
    expect(
        effectiveRecordingRedaction(
            globalEnabled: true, host: h(redaction: false)),
        isFalse);
  });

  test('global off wins over host on', () {
    expect(
        effectiveRecordingRedaction(
            globalEnabled: false, host: h(redaction: true)),
        isFalse);
  });

  test('global off + host off = no redaction', () {
    expect(
        effectiveRecordingRedaction(
            globalEnabled: false, host: h(redaction: false)),
        isFalse);
  });

  test('local shell (no host) follows the global toggle alone', () {
    expect(effectiveRecordingRedaction(globalEnabled: true, host: null), isTrue);
    expect(
        effectiveRecordingRedaction(globalEnabled: false, host: null), isFalse);
  });
}
