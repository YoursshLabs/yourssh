import 'dart:io';
import 'package:uuid/uuid.dart';

enum KeyAlgorithm { ed25519, rsa, ecdsa }

class SshKeyEntry {
  final String id;
  String label;
  KeyAlgorithm algorithm;
  String publicKey;
  String privateKeyPath; // path on disk or 'embedded'
  String? certificatePath;
  DateTime addedAt;

  SshKeyEntry({
    String? id,
    required this.label,
    required this.algorithm,
    required this.publicKey,
    required this.privateKeyPath,
    this.certificatePath,
    DateTime? addedAt,
  })  : id = id ?? const Uuid().v4(),
        addedAt = addedAt ?? DateTime.now();

  bool get hasCertificate =>
      certificatePath != null && File(certificatePath!).existsSync();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'algorithm': algorithm.name,
        'publicKey': publicKey,
        'privateKeyPath': privateKeyPath,
        'certificatePath': certificatePath,
        'addedAt': addedAt.toIso8601String(),
      };

  factory SshKeyEntry.fromJson(Map<String, dynamic> json) => SshKeyEntry(
        id: json['id'],
        label: json['label'],
        algorithm: KeyAlgorithm.values.byName(json['algorithm'] ?? 'rsa'),
        publicKey: json['publicKey'] ?? '',
        privateKeyPath: json['privateKeyPath'] ?? '',
        certificatePath: json['certificatePath'] as String?,
        addedAt: DateTime.parse(json['addedAt']),
      );

  String get algorithmLabel => switch (algorithm) {
        KeyAlgorithm.ed25519 => 'Ed25519',
        KeyAlgorithm.rsa => 'RSA',
        KeyAlgorithm.ecdsa => 'ECDSA',
      };

  String get fingerprint {
    if (publicKey.isEmpty) return '';
    final parts = publicKey.split(' ');
    return parts.length > 1 ? '${parts[0]}...${parts[1].substring(0, 16)}' : '';
  }
}
