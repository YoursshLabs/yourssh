import 'package:uuid/uuid.dart';

enum ForwardType { local, remote, dynamic }

enum ForwardStatus { idle, active, error }

class PortForward {
  final String id;
  String label;
  ForwardType type;
  String localHost;
  int localPort;
  String remoteHost;
  int remotePort;
  String? hostId;
  ForwardStatus status;
  String? errorMessage;

  PortForward({
    String? id,
    required this.label,
    required this.type,
    this.localHost = '127.0.0.1',
    required this.localPort,
    this.remoteHost = '',
    this.remotePort = 0,
    this.hostId,
    this.status = ForwardStatus.idle,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'localHost': localHost,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
        'hostId': hostId,
      };

  factory PortForward.fromJson(Map<String, dynamic> json) => PortForward(
        id: json['id'],
        label: json['label'],
        type: ForwardType.values.byName(json['type'] ?? 'local'),
        localHost: json['localHost'] ?? '127.0.0.1',
        localPort: json['localPort'] ?? 0,
        remoteHost: json['remoteHost'] ?? '',
        remotePort: json['remotePort'] ?? 0,
        hostId: json['hostId'],
      );

  String get typeLabel => switch (type) {
        ForwardType.local => 'Local',
        ForwardType.remote => 'Remote',
        ForwardType.dynamic => 'Dynamic SOCKS5',
      };

  String get summary => switch (type) {
        ForwardType.local => '$localHost:$localPort → $remoteHost:$remotePort',
        ForwardType.remote => 'Remote $remotePort → $localHost:$localPort',
        ForwardType.dynamic => '$localHost:$localPort (SOCKS5)',
      };
}
