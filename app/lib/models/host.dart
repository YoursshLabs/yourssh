import 'package:uuid/uuid.dart';

enum AuthType { password, privateKey, certificate, agent }

/// How SFTP sessions are started on this host. [normal] requests the
/// standard `sftp` subsystem; [sudo] runs the sftp-server binary through
/// `sudo` on an exec channel (root SFTP); [custom] runs
/// [Host.sftpServerCommand] verbatim on an exec channel.
enum SftpMode { normal, sudo, custom }

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
  String? jumpHostId;
  bool shellIntegration;
  SftpMode sftpMode;
  String? sftpServerCommand;

  Host({
    String? id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = AuthType.password,
    this.keyId,
    this.group = '',
    List<String> tags = const [],
    DateTime? createdAt,
    this.detectedOs,
    this.autoRecord = false,
    this.jumpHostId,
    this.shellIntegration = true,
    this.sftpMode = SftpMode.normal,
    this.sftpServerCommand,
  })  : id = id ?? const Uuid().v4(),
        // Always own a growable copy so callers can `tags.add(...)`
        // without hitting `Unsupported operation` on the shared `const []`.
        tags = List.of(tags),
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
        'jumpHostId': jumpHostId,
        'shellIntegration': shellIntegration,
        'sftpMode': sftpMode.name,
        'sftpServerCommand': sftpServerCommand,
      };

  /// Tolerant of partially-missing fields so a corrupted prefs blob or
  /// forward-compat sync payload doesn't crash startup. Required `host` /
  /// `username` still throw when truly absent so we don't silently restore
  /// an unusable entry.
  factory Host.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as String?;
    final username = json['username'] as String?;
    if (host == null || host.isEmpty || username == null || username.isEmpty) {
      throw FormatException('Host JSON missing required host/username: $json');
    }
    DateTime parseCreatedAt() {
      final raw = json['createdAt'];
      if (raw is String) {
        try { return DateTime.parse(raw); } catch (_) {}
      }
      return DateTime.now();
    }
    AuthType parseAuth() {
      final name = json['authType'] as String?;
      if (name == null) return AuthType.password;
      // Unknown values throw — silently downgrading would hide data-corruption
      // or version-mismatch bugs.
      return AuthType.values.byName(name);
    }
    SftpMode parseSftpMode() {
      final name = json['sftpMode'] as String?;
      // Unknown/forward-compat values degrade to normal rather than throwing:
      // sftpMode is new and a target of cross-version sync, so a single host
      // carrying a future mode must not abort loading the whole list.
      return SftpMode.values.asNameMap()[name] ?? SftpMode.normal;
    }
    return Host(
      id: json['id'] as String?,
      label: (json['label'] as String?) ?? host,
      host: host,
      port: (json['port'] as int?) ?? 22,
      username: username,
      authType: parseAuth(),
      keyId: json['keyId'] as String?,
      group: (json['group'] as String?) ?? '',
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      createdAt: parseCreatedAt(),
      detectedOs: json['detectedOs'] as String?,
      autoRecord: (json['autoRecord'] as bool?) ?? false,
      jumpHostId: json['jumpHostId'] as String?,
      shellIntegration: (json['shellIntegration'] as bool?) ?? true,
      sftpMode: parseSftpMode(),
      sftpServerCommand: json['sftpServerCommand'] as String?,
    );
  }

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
    Object? jumpHostId = const _Unset(),
    bool? shellIntegration,
    SftpMode? sftpMode,
    Object? sftpServerCommand = const _Unset(),
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
        jumpHostId: jumpHostId is _Unset ? this.jumpHostId : jumpHostId as String?,
        shellIntegration: shellIntegration ?? this.shellIntegration,
        sftpMode: sftpMode ?? this.sftpMode,
        sftpServerCommand: sftpServerCommand is _Unset
            ? this.sftpServerCommand
            : sftpServerCommand as String?,
      );
}

class _Unset { const _Unset(); }
