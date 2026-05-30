import 'dart:async';
import 'dart:typed_data';

class KnownHost {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final DateTime addedAt;

  const KnownHost({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.addedAt,
  });

  String get lookupKey => '$host:$port:$keyType';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'keyType': keyType,
        'fingerprint': fingerprint,
        'addedAt': addedAt.toIso8601String(),
      };

  factory KnownHost.fromJson(Map<String, dynamic> json) => KnownHost(
        host: json['host'] as String,
        port: json['port'] as int,
        keyType: json['keyType'] as String,
        fingerprint: json['fingerprint'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  static String bytesToFingerprint(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}

class HostKeyChallenge {
  /// Maximum time the UI has to respond to a host-key prompt before the
  /// connect is auto-rejected. Without this, dismissing the dialog with no
  /// answer hangs the connect future indefinitely.
  static const _timeout = Duration(minutes: 2);

  final String host;
  final int port;
  final String keyType;
  final String oldFingerprint;
  final String newFingerprint;
  final _completer = Completer<bool>();
  Timer? _timeoutTimer;

  HostKeyChallenge({
    required this.host,
    required this.port,
    required this.keyType,
    required this.oldFingerprint,
    required this.newFingerprint,
  }) {
    _timeoutTimer = Timer(_timeout, () => resolve(false));
  }

  void resolve(bool trust) {
    if (_completer.isCompleted) return;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _completer.complete(trust);
  }

  /// Marks the challenge as rejected. Idempotent — safe to call multiple times.
  void reject() => resolve(false);

  Future<bool> get result => _completer.future;
}
