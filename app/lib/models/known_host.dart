import 'dart:async';
import 'dart:typed_data';

class KnownHost {
  /// Wire values for [protocol] — use these instead of bare literals so a
  /// typo can't silently fail an equality check.
  static const protocolSsh = 'ssh';
  static const protocolRdp = 'rdp';

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final DateTime addedAt;
  /// [protocolSsh] (default) or [protocolRdp]. Added additively — old rows
  /// default to ssh.
  final String protocol;

  const KnownHost({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.addedAt,
    this.protocol = protocolSsh,
  });

  String get lookupKey => '$host:$port:$keyType';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'keyType': keyType,
        'fingerprint': fingerprint,
        'addedAt': addedAt.toIso8601String(),
        'protocol': protocol,
      };

  factory KnownHost.fromJson(Map<String, dynamic> json) => KnownHost(
        host: json['host'] as String,
        port: json['port'] as int,
        keyType: json['keyType'] as String,
        fingerprint: json['fingerprint'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
        protocol: json['protocol'] as String? ?? protocolSsh,
      );

  static String bytesToFingerprint(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}

/// Result of checking a pinned RDP certificate fingerprint.
enum RdpCertVerdict { trusted, unknown, mismatch }

/// Shared completer/timeout machinery for trust-on-first-use prompts.
/// The UI gets [_timeout] to answer before the connect is auto-rejected —
/// without it, dismissing the dialog with no answer hangs the connect
/// future indefinitely.
abstract class TofuChallenge {
  static const _timeout = Duration(minutes: 2);

  final _completer = Completer<bool>();
  Timer? _timeoutTimer;

  TofuChallenge() {
    _timeoutTimer = Timer(_timeout, () => resolve(false));
  }

  /// Idempotent — later calls (timeout firing after the user answered,
  /// a replacement challenge rejecting this one twice) are no-ops.
  void resolve(bool trust) {
    if (_completer.isCompleted) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _completer.complete(trust);
  }

  void reject() => resolve(false);

  /// True once answered (or timed out) — lets the UI skip re-showing a
  /// dialog for a challenge that is already settled but not yet cleared
  /// from the provider (the awaiting caller clears it asynchronously).
  bool get isResolved => _completer.isCompleted;

  Future<bool> get result => _completer.future;
}

/// Async TOFU challenge for an RDP server certificate.
class RdpCertChallenge extends TofuChallenge {
  final String host;
  final int port;
  final String fingerprint;
  final bool isMismatch;

  RdpCertChallenge({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.isMismatch,
  });
}

/// Async TOFU challenge for a changed SSH host key.
class HostKeyChallenge extends TofuChallenge {
  final String host;
  final int port;
  final String keyType;
  final String oldFingerprint;
  final String newFingerprint;

  HostKeyChallenge({
    required this.host,
    required this.port,
    required this.keyType,
    required this.oldFingerprint,
    required this.newFingerprint,
  });
}
