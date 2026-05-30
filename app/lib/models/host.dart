import 'package:uuid/uuid.dart';

enum AuthType { password, privateKey, certificate, agent }

class Host {
  final String id;
  String label;
  String host;
  int port;
  String username;
  AuthType authType;
  String? keyId;
  String group;
  List<String> tags;
  DateTime createdAt;
  String? detectedOs;
  bool autoRecord;

  Host({
    String? id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = AuthType.password,
    this.keyId,
    this.group = '',
    this.tags = const [],
    DateTime? createdAt,
    this.detectedOs,
    this.autoRecord = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType.name,
        'keyId': keyId,
        'group': group,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'detectedOs': detectedOs,
        'autoRecord': autoRecord,
      };

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'],
        label: json['label'],
        host: json['host'],
        port: json['port'] ?? 22,
        username: json['username'],
        authType: AuthType.values.byName(json['authType'] ?? 'password'),
        keyId: json['keyId'],
        group: json['group'] ?? '',
        tags: List<String>.from(json['tags'] ?? []),
        createdAt: DateTime.parse(json['createdAt']),
        detectedOs: json['detectedOs'] as String?,
        autoRecord: (json['autoRecord'] as bool?) ?? false,
      );

  Host copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    AuthType? authType,
    String? keyId,
    String? group,
    String? detectedOs,
    bool? autoRecord,
  }) =>
      Host(
        id: id,
        label: label ?? this.label,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authType: authType ?? this.authType,
        keyId: keyId ?? this.keyId,
        group: group ?? this.group,
        tags: tags,
        createdAt: createdAt,
        detectedOs: detectedOs ?? this.detectedOs,
        autoRecord: autoRecord ?? this.autoRecord,
      );
}
