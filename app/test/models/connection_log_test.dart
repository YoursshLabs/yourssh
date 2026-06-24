import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/connection_log.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

SshSession _session() => SshSession(
      host: Host(id: 'h1', label: 'Box', host: 'example.com', port: 22, username: 'root'),
    );

void main() {
  group('SshSession.logConnection', () {
    test('starts empty', () {
      expect(_session().connectionLog, isEmpty);
    });

    test('appends a line with the given level and message', () {
      final s = _session();
      s.logConnection(ConnectionLogLevel.info, 'Connecting…');
      s.logConnection(ConnectionLogLevel.success, 'Connected');

      expect(s.connectionLog, hasLength(2));
      expect(s.connectionLog.first.level, ConnectionLogLevel.info);
      expect(s.connectionLog.first.message, 'Connecting…');
      expect(s.connectionLog.last.level, ConnectionLogLevel.success);
    });

    test('uses the provided timestamp when given', () {
      final s = _session();
      final t = DateTime(2026, 6, 23, 10, 30, 45);
      s.logConnection(ConnectionLogLevel.info, 'x', at: t);
      expect(s.connectionLog.single.time, t);
    });

    test('bounds the log to the most recent kMaxConnectionLogLines', () {
      final s = _session();
      for (var i = 0; i < kMaxConnectionLogLines + 50; i++) {
        s.logConnection(ConnectionLogLevel.info, 'line $i');
      }
      expect(s.connectionLog, hasLength(kMaxConnectionLogLines));
      // Oldest lines dropped; the newest line is retained.
      expect(s.connectionLog.last.message, 'line ${kMaxConnectionLogLines + 49}');
      expect(s.connectionLog.first.message, 'line 50');
    });

    test('clearConnectionLog empties the buffer', () {
      final s = _session()
        ..logConnection(ConnectionLogLevel.info, 'a')
        ..logConnection(ConnectionLogLevel.error, 'b');
      s.clearConnectionLog();
      expect(s.connectionLog, isEmpty);
    });
  });
}
