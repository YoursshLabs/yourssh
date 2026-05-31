import 'dart:convert';

class ManifestException implements Exception {
  final String message;
  const ManifestException(this.message);
  @override
  String toString() => 'ManifestException: $message';
}

const _kValidId = r'^[a-z0-9][a-z0-9._\-]{0,63}$';

const _kKnownPermissions = {
  'terminal.read',
  'terminal.transform',
  'terminal.intercept',
  'terminal.inject',
  'session.observe',
  'session.control',
  'ssh.exec',
  'sftp.read',
  'sftp.write',
  'command.intercept',
  'ui.notify',
  'ui.statusbar',
  'ui.panel',
  'ui.clipboard',
};

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String entry;
  final String minAppVersion;
  final Set<String> permissions;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.minAppVersion,
    required this.permissions,
  });

  factory PluginManifest.fromJson(String raw) {
    final Map<String, dynamic> m;
    try {
      m = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const ManifestException('plugin.json is not valid JSON');
    }

    String req(String key) {
      final v = m[key];
      if (v == null || v is! String || v.isEmpty) {
        throw ManifestException('plugin.json missing required field: $key');
      }
      return v;
    }

    final id = req('id');
    if (!RegExp(_kValidId).hasMatch(id)) {
      throw ManifestException('Invalid plugin id: "$id"');
    }

    final rawPerms = (m['permissions'] as List?)?.cast<String>() ?? [];
    final unknown = rawPerms.toSet().difference(_kKnownPermissions);
    if (unknown.isNotEmpty) {
      throw ManifestException('Unknown permissions: $unknown');
    }

    return PluginManifest(
      id: id,
      name: req('name'),
      version: req('version'),
      entry: req('entry'),
      minAppVersion: req('minAppVersion'),
      permissions: rawPerms.toSet(),
    );
  }
}
