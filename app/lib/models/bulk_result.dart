import 'host.dart';

/// Lifecycle of one host inside a bulk run.
enum BulkHostStatus { pending, running, success, failed, cancelled }

/// Immutable snapshot of one host's progress/result in a bulk run.
///
/// For exec runs, [BulkHostStatus.success] means the command ran — a
/// non-zero [exitCode] is still success (the command's own failure is data
/// shown in the row); [BulkHostStatus.failed] means the app could not run
/// it at all (connect, auth, timeout, channel error).
class BulkHostResult {
  final Host host;
  final BulkHostStatus status;
  final int? exitCode; // exec only
  final String stdout; // exec only
  final String stderr; // exec only
  final String? error; // connect/auth/timeout/transfer error
  final Duration? elapsed;
  final int bytesTransferred; // push only
  final int totalBytes; // push only

  const BulkHostResult({
    required this.host,
    required this.status,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.error,
    this.elapsed,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
  });

  /// `SshService.exec` reports -1 when the server sent no exit status
  /// (killed by a signal, or a server that never reports one).
  bool get exitUnknown => status == BulkHostStatus.success && exitCode == -1;

  /// Exec ran and reported a non-zero (or unknown) exit status. One rule for
  /// the row and the footer: such a host is a warning, never counted as "ok".
  bool get exitedNonZero =>
      status == BulkHostStatus.success && exitCode != null && exitCode != 0;

  /// Ran to completion with exit 0 (a push has no exit code: success = clean).
  bool get ranClean => status == BulkHostStatus.success && !exitedNonZero;
}
