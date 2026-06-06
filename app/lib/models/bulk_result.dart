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
}
