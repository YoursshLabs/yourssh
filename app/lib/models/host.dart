import 'package:uuid/uuid.dart';

enum AuthType { password, privateKey, certificate, agent }

/// How SFTP sessions are started on this host. [normal] requests the
/// standard `sftp` subsystem; [sudo] runs the sftp-server binary through
/// `sudo` on an exec channel (root SFTP); [custom] runs
/// [Host.sftpServerCommand] verbatim on an exec channel.
enum SftpMode { normal, sudo, custom }

/// Transport protocol. Legacy hosts without the field parse as [ssh].
enum HostProtocol {
  ssh(defaultPort: 22),
  rdp(defaultPort: 3389);

  const HostProtocol({required this.defaultPort});

  /// Canonical port for the protocol — the single source for the host form's
  /// default value and its auto-flip when the protocol changes.
  final int defaultPort;
}

/// RDP security mode. [auto] lets the server negotiate; [nla] forces
/// CredSSP/NLA; [tls] disables NLA and uses TLS-only.
enum RdpSecurityMode { auto, nla, tls }

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

  /// Mask secrets (AuditRedactor patterns) in this host's recordings.
  /// Effective only while the global Settings toggle is also on.
  bool recordingRedaction;

  /// Ordered jump-host chain (bastion → … → target). Empty = direct.
  List<String> jumpHostIds;
  bool shellIntegration;
  bool agentForwarding;
  SftpMode sftpMode;
  String? sftpServerCommand;

  // ── RDP-specific fields ──────────────────────────────────────────────
  HostProtocol protocol;
  String? domain;
  RdpSecurityMode rdpSecurity;

  // ── Session template (per-host preset) ──────────────────────────────
  // All null/empty = no override; see
  // docs/superpowers/specs/2026-06-06-session-template-design.md.
  String? workingDir;
  Map<String, String> envVars;
  String? startupSnippet;
  String? terminalThemeId;
  String? fontFamily;
  double? fontSize;
  String? termType;
  bool? tmuxOverride;

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
    this.recordingRedaction = true,
    Iterable<String> jumpHostIds = const [],
    this.shellIntegration = true,
    this.agentForwarding = false,
    this.sftpMode = SftpMode.normal,
    this.sftpServerCommand,
    this.protocol = HostProtocol.ssh,
    this.domain,
    this.rdpSecurity = RdpSecurityMode.auto,
    this.workingDir,
    Map<String, String> envVars = const {},
    this.startupSnippet,
    this.terminalThemeId,
    this.fontFamily,
    this.fontSize,
    this.termType,
    this.tmuxOverride,
  })  : id = id ?? const Uuid().v4(),
        // Always own a growable copy so callers can `tags.add(...)`
        // without hitting `Unsupported operation` on the shared `const []`.
        tags = List.of(tags),
        envVars = Map.of(envVars),
        jumpHostIds = List.of(jumpHostIds),
        createdAt = createdAt ?? DateTime.now();

  /// First hop, for "has a bastion?" consumers and cross-version JSON.
  String? get jumpHostId => jumpHostIds.isEmpty ? null : jumpHostIds.first;

  /// Whether connect-time template work exists. Drives the invisible
  /// handshake when shell integration is off — the snippet needs the
  /// handshake too, since DONE is its send trigger.
  bool get hasTemplateSetup =>
      workingDir != null || envVars.isNotEmpty || startupSnippet != null;

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
        'recordingRedaction': recordingRedaction,
        'jumpHostIds': jumpHostIds,
        // Dual-write the first hop so an older app reading a synced payload
        // keeps a working single-hop bastion instead of losing it.
        'jumpHostId': jumpHostId,
        'shellIntegration': shellIntegration,
        'agentForwarding': agentForwarding,
        'sftpMode': sftpMode.name,
        'sftpServerCommand': sftpServerCommand,
        'protocol': protocol.name,
        'domain': domain,
        'rdpSecurity': rdpSecurity.name,
        'workingDir': workingDir,
        'envVars': envVars,
        'startupSnippet': startupSnippet,
        'terminalThemeId': terminalThemeId,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'termType': termType,
        'tmuxOverride': tmuxOverride,
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
    HostProtocol parseProtocol() {
      final name = json['protocol'] as String?;
      return HostProtocol.values.asNameMap()[name] ?? HostProtocol.ssh;
    }
    RdpSecurityMode parseRdpSecurity() {
      final name = json['rdpSecurity'] as String?;
      return RdpSecurityMode.values.asNameMap()[name] ?? RdpSecurityMode.auto;
    }
    Map<String, String> parseEnvVars() {
      final raw = json['envVars'];
      // Malformed/forward-compat values degrade to empty rather than
      // throwing: a single bad host in a sync payload must not abort
      // loading the whole list.
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    List<String> parseJumpHostIds() {
      final raw = json['jumpHostIds'];
      if (raw is List) {
        // Keep only real string ids — a null/int/empty element can't match a
        // host and would just trip the "jump host not found" path.
        return raw.whereType<String>().where((s) => s.isNotEmpty).toList();
      }
      // Legacy single-hop payload.
      final legacy = json['jumpHostId'];
      return legacy is String && legacy.isNotEmpty ? [legacy] : const [];
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
      recordingRedaction: (json['recordingRedaction'] as bool?) ?? true,
      jumpHostIds: parseJumpHostIds(),
      shellIntegration: (json['shellIntegration'] as bool?) ?? true,
      agentForwarding: (json['agentForwarding'] as bool?) ?? false,
      sftpMode: parseSftpMode(),
      sftpServerCommand: json['sftpServerCommand'] as String?,
      protocol: parseProtocol(),
      domain: json['domain'] as String?,
      rdpSecurity: parseRdpSecurity(),
      workingDir: json['workingDir'] as String?,
      envVars: parseEnvVars(),
      startupSnippet: json['startupSnippet'] as String?,
      terminalThemeId: json['terminalThemeId'] as String?,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      termType: json['termType'] as String?,
      tmuxOverride: json['tmuxOverride'] as bool?,
    );
  }

  Host copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    AuthType? authType,
    Object? keyId = const _Unset(),
    String? group,
    String? detectedOs,
    bool? autoRecord,
    bool? recordingRedaction,
    List<String>? jumpHostIds,
    bool? shellIntegration,
    bool? agentForwarding,
    SftpMode? sftpMode,
    Object? sftpServerCommand = const _Unset(),
    HostProtocol? protocol,
    Object? domain = const _Unset(),
    RdpSecurityMode? rdpSecurity,
    Object? workingDir = const _Unset(),
    Map<String, String>? envVars,
    Object? startupSnippet = const _Unset(),
    Object? terminalThemeId = const _Unset(),
    Object? fontFamily = const _Unset(),
    Object? fontSize = const _Unset(),
    Object? termType = const _Unset(),
    Object? tmuxOverride = const _Unset(),
  }) =>
      Host(
        id: id,
        label: label ?? this.label,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authType: authType ?? this.authType,
        keyId: keyId is _Unset ? this.keyId : keyId as String?,
        group: group ?? this.group,
        tags: tags,
        createdAt: createdAt,
        detectedOs: detectedOs ?? this.detectedOs,
        autoRecord: autoRecord ?? this.autoRecord,
        recordingRedaction: recordingRedaction ?? this.recordingRedaction,
        jumpHostIds: jumpHostIds ?? this.jumpHostIds,
        shellIntegration: shellIntegration ?? this.shellIntegration,
        agentForwarding: agentForwarding ?? this.agentForwarding,
        sftpMode: sftpMode ?? this.sftpMode,
        sftpServerCommand: sftpServerCommand is _Unset
            ? this.sftpServerCommand
            : sftpServerCommand as String?,
        protocol: protocol ?? this.protocol,
        domain: domain is _Unset ? this.domain : domain as String?,
        rdpSecurity: rdpSecurity ?? this.rdpSecurity,
        workingDir:
            workingDir is _Unset ? this.workingDir : workingDir as String?,
        envVars: envVars ?? this.envVars,
        startupSnippet: startupSnippet is _Unset
            ? this.startupSnippet
            : startupSnippet as String?,
        terminalThemeId: terminalThemeId is _Unset
            ? this.terminalThemeId
            : terminalThemeId as String?,
        fontFamily:
            fontFamily is _Unset ? this.fontFamily : fontFamily as String?,
        fontSize: fontSize is _Unset ? this.fontSize : fontSize as double?,
        termType: termType is _Unset ? this.termType : termType as String?,
        tmuxOverride:
            tmuxOverride is _Unset ? this.tmuxOverride : tmuxOverride as bool?,
      );
}

class _Unset { const _Unset(); }
