import 'ssh_session.dart';

/// Health tier of a live SSH connection, derived from round-trip ping latency.
enum HealthStatus { healthy, degraded, down, offline }

/// Visual tone for the session-tab health dot. [connecting] is rendered as a
/// pulsing amber dot; the rest are static colors.
enum BadgeTone { green, amber, red, grey, connecting }

/// Immutable health snapshot for one host connection.
class SessionHealth {
  final HealthStatus status;
  final int? latencyMs;
  final DateTime? lastPingAt;

  const SessionHealth({required this.status, this.latencyMs, this.lastPingAt});

  /// No reading yet (or host not connected).
  static const offline = SessionHealth(status: HealthStatus.offline);

  /// Map a measured latency (ms) to a status. `null` means the ping failed or
  /// timed out — treated as [HealthStatus.down] for a connected host.
  factory SessionHealth.fromLatency(int? ms, {DateTime? at}) {
    if (ms == null) {
      return SessionHealth(status: HealthStatus.down, lastPingAt: at);
    }
    final HealthStatus status;
    if (ms < 150) {
      status = HealthStatus.healthy;
    } else if (ms <= 500) {
      status = HealthStatus.degraded;
    } else {
      status = HealthStatus.down;
    }
    return SessionHealth(status: status, latencyMs: ms, lastPingAt: at);
  }
}

/// Resolve the badge tone. [SessionStatus] (lifecycle) takes precedence over
/// [SessionHealth] (ping result); health only matters while connected.
BadgeTone badgeToneFor(SessionStatus status, SessionHealth health) {
  switch (status) {
    case SessionStatus.connecting:
      return BadgeTone.connecting;
    case SessionStatus.disconnected:
      return BadgeTone.grey;
    case SessionStatus.error:
      return BadgeTone.red;
    case SessionStatus.connected:
      switch (health.status) {
        case HealthStatus.healthy:
          return BadgeTone.green;
        case HealthStatus.degraded:
          return BadgeTone.amber;
        case HealthStatus.down:
          return BadgeTone.red;
        case HealthStatus.offline:
          return BadgeTone.grey;
      }
  }
}
