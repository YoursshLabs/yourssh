// app/test/models/session_health_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/session_health.dart';
import 'package:yourssh/models/ssh_session.dart';

void main() {
  group('SessionHealth.fromLatency', () {
    test('maps latency to status by threshold', () {
      expect(SessionHealth.fromLatency(0).status, HealthStatus.healthy);
      expect(SessionHealth.fromLatency(149).status, HealthStatus.healthy);
      expect(SessionHealth.fromLatency(150).status, HealthStatus.degraded);
      expect(SessionHealth.fromLatency(500).status, HealthStatus.degraded);
      expect(SessionHealth.fromLatency(501).status, HealthStatus.down);
      expect(SessionHealth.fromLatency(null).status, HealthStatus.down);
    });

    test('keeps the measured latency value', () {
      expect(SessionHealth.fromLatency(42).latencyMs, 42);
      expect(SessionHealth.fromLatency(null).latencyMs, isNull);
    });

    test('offline constant has offline status and no latency', () {
      expect(SessionHealth.offline.status, HealthStatus.offline);
      expect(SessionHealth.offline.latencyMs, isNull);
    });
  });

  group('badgeToneFor', () {
    test('session status takes precedence over health', () {
      const healthy = SessionHealth(status: HealthStatus.healthy);
      expect(badgeToneFor(SessionStatus.connecting, healthy), BadgeTone.connecting);
      expect(badgeToneFor(SessionStatus.disconnected, healthy), BadgeTone.grey);
      expect(badgeToneFor(SessionStatus.error, healthy), BadgeTone.red);
    });

    test('connected maps from health status', () {
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.healthy)), BadgeTone.green);
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.degraded)), BadgeTone.amber);
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.down)), BadgeTone.red);
      expect(badgeToneFor(SessionStatus.connected, const SessionHealth(status: HealthStatus.offline)), BadgeTone.grey);
    });
  });
}
