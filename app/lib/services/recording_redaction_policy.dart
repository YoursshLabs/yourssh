import '../models/host.dart';

/// Effective recording redaction: the global Settings toggle AND the
/// per-host flag. A local shell session has no [host] (pass null) and
/// follows the global toggle alone.
///
/// Pure — unit-tested in test/services/recording_redaction_policy_test.dart;
/// main.dart resolves [host] with a fresh HostProvider lookup (the session's
/// connect-time snapshot goes stale after a panel edit).
bool effectiveRecordingRedaction({required bool globalEnabled, Host? host}) =>
    globalEnabled && (host?.recordingRedaction ?? true);
