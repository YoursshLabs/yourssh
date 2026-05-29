import 'package:uuid/uuid.dart';

enum TunnelStatus { idle, starting, active, error }

enum TunnelType { cloudflare, sshForward }

class TunnelConfig {
  final String id;
  final String label;
  final TunnelType type;
  final int localPort;
  String? publicUrl;
  TunnelStatus status;
  String? errorMessage;

  TunnelConfig({
    String? id,
    required this.label,
    required this.type,
    required this.localPort,
    this.publicUrl,
    this.status = TunnelStatus.idle,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'localPort': localPort,
      };

  factory TunnelConfig.fromJson(Map<String, dynamic> json) => TunnelConfig(
        id: json['id'] as String,
        label: json['label'] as String,
        type: TunnelType.values.byName(json['type'] as String),
        localPort: json['localPort'] as int,
      );
}
