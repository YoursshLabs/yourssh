import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:yourssh/models/host.dart';

typedef ParseResult = ({List<Host> hosts, List<String> warnings});

abstract class ImportParser {
  const ImportParser();
  ParseResult parse(String input);
}

// ── SSH Config ────────────────────────────────────────────

class SshConfigParser extends ImportParser {
  const SshConfigParser();

  @override
  ParseResult parse(String input) {
    final hosts = <Host>[];
    final blockRegex = RegExp(r'^Host\s+(.+)$', multiLine: true, caseSensitive: false);
    final matches = blockRegex.allMatches(input).toList();
    for (var i = 0; i < matches.length; i++) {
      final alias = matches[i].group(1)!.trim();
      if (alias == '*') continue;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : input.length;
      final block = input.substring(start, end);
      String? hostname;
      String user = 'root';
      int port = 22;
      for (final line in block.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.toLowerCase().startsWith('hostname ')) {
          hostname = trimmed.substring('hostname '.length).trim();
        } else if (trimmed.toLowerCase().startsWith('user ')) {
          user = trimmed.substring('user '.length).trim();
        } else if (trimmed.toLowerCase().startsWith('port ')) {
          port = int.tryParse(trimmed.substring('port '.length).trim()) ?? 22;
        }
      }
      if (hostname == null) continue;
      hosts.add(Host(label: alias, host: hostname, port: port, username: user));
    }
    return (hosts: hosts, warnings: const []);
  }
}

// ── CSV ───────────────────────────────────────────────────

List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        sb.write('"');
        i += 2;
      } else {
        inQuotes = !inQuotes;
        i++;
      }
    } else if (ch == ',' && !inQuotes) {
      fields.add(sb.toString());
      sb.clear();
      i++;
    } else {
      sb.write(ch);
      i++;
    }
  }
  if (inQuotes) throw FormatException('Unterminated quote in CSV');
  fields.add(sb.toString());
  return fields;
}

class CsvParser extends ImportParser {
  const CsvParser();

  @override
  ParseResult parse(String input) {
    final lines = input.split('\n').map((l) => l.trimRight()).toList();
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return (hosts: [], warnings: []);

    final header =
        _splitCsvLine(lines[0]).map((h) => h.trim().toLowerCase()).toList();
    if (!header.contains('host')) {
      throw FormatException("CSV missing required 'host' column");
    }

    int idx(String name) => header.indexOf(name);
    final hostIdx = idx('host');
    final labelIdx = idx('label');
    final portIdx = idx('port');
    final userIdx = idx('username');
    final authIdx = idx('auth_type');
    final groupIdx = idx('group');
    final tagsIdx = idx('tags');

    final hosts = <Host>[];
    final warnings = <String>[];

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      List<String> cells;
      try {
        cells = _splitCsvLine(line);
      } catch (_) {
        warnings.add('Row ${i + 1}: malformed CSV, skipped');
        continue;
      }

      String cell(int colIdx) =>
          colIdx >= 0 && colIdx < cells.length ? cells[colIdx].trim() : '';

      final hostVal = cell(hostIdx);
      if (hostVal.isEmpty) {
        warnings.add('Row ${i + 1}: missing host, skipped');
        continue;
      }

      int port = 22;
      final portStr = cell(portIdx);
      if (portStr.isNotEmpty) {
        final parsed = int.tryParse(portStr);
        if (parsed == null || parsed < 1 || parsed > 65535) {
          warnings.add("Row ${i + 1}: invalid port '$portStr', skipped");
          continue;
        }
        port = parsed;
      }

      final labelVal = cell(labelIdx);
      final authVal = cell(authIdx).toLowerCase();
      final tagsVal = cell(tagsIdx);

      final authType = switch (authVal) {
        'key' || 'privatekey' => AuthType.privateKey,
        'agent' => AuthType.agent,
        _ => AuthType.password,
      };

      final tags = tagsVal.isEmpty
          ? <String>[]
          : tagsVal
              .split(';')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList();

      hosts.add(Host(
        label: labelVal.isEmpty ? hostVal : labelVal,
        host: hostVal,
        port: port,
        username: cell(userIdx),
        authType: authType,
        group: cell(groupIdx),
        tags: tags,
      ));
    }

    return (hosts: hosts, warnings: warnings);
  }
}

// ── PuTTY Registry Export ─────────────────────────────────

class PuttyRegParser extends ImportParser {
  const PuttyRegParser();

  static final _sectionRe = RegExp(
    r'^\[HKEY_[^\]]*\\Sessions\\([^\]]+)\]',
    multiLine: true,
    caseSensitive: false,
  );
  static final _hostRe =
      RegExp(r'^"HostName"="([^"]*)"', multiLine: true);
  static final _portRe =
      RegExp(r'^"PortNumber"=dword:([0-9a-fA-F]+)', multiLine: true);
  static final _userRe =
      RegExp(r'^"UserName"="([^"]*)"', multiLine: true);

  @override
  ParseResult parse(String input) {
    var text = input;
    if (text.startsWith('﻿')) text = text.substring(1); // strip UTF-8 BOM

    final hosts = <Host>[];
    final warnings = <String>[];
    final sections = _sectionRe.allMatches(text).toList();

    for (var i = 0; i < sections.length; i++) {
      final rawName = sections[i].group(1)!;
      final name = Uri.decodeComponent(rawName.replaceAll('+', ' '));
      final start = sections[i].end;
      final end =
          i + 1 < sections.length ? sections[i + 1].start : text.length;
      final block = text.substring(start, end);

      final hostname = _hostRe.firstMatch(block)?.group(1);
      if (hostname == null || hostname.isEmpty) {
        warnings.add('Session "$name": missing HostName, skipped');
        continue;
      }
      final portHex = _portRe.firstMatch(block)?.group(1) ?? '16';
      final port = int.tryParse(portHex, radix: 16) ?? 22;
      final user = _userRe.firstMatch(block)?.group(1) ?? 'root';

      hosts.add(Host(label: name, host: hostname, port: port, username: user));
    }

    return (hosts: hosts, warnings: warnings);
  }
}

// ── MobaXterm ─────────────────────────────────────────────

class MobaXtermParser extends ImportParser {
  const MobaXtermParser();

  @override
  ParseResult parse(String input) {
    final hosts = <Host>[];
    final warnings = <String>[];

    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('[')) continue;

      final eqIdx = line.indexOf('=');
      if (eqIdx < 0) continue;

      final label = line.substring(0, eqIdx).trim();
      if (label == 'SubRep' || label == 'ImgNum') continue;

      final valuePart = line.substring(eqIdx + 1).trim();
      final tokens = valuePart
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

      if (tokens.isEmpty || tokens[0] != '0') continue; // SSH only

      if (tokens.length < 4) {
        warnings.add('Session "$label": malformed line, skipped');
        continue;
      }

      final host = tokens[1];
      final port = int.tryParse(tokens[2]) ?? 22;
      final user = tokens[3];

      if (host.isEmpty) {
        warnings.add('Session "$label": missing host, skipped');
        continue;
      }

      hosts.add(Host(label: label, host: host, port: port, username: user));
    }

    return (hosts: hosts, warnings: warnings);
  }
}

// ── SecureCRT XML ─────────────────────────────────────────

class SecureCrtParser extends ImportParser {
  const SecureCrtParser();

  @override
  ParseResult parse(String input) {
    if (input.trim().isEmpty) return (hosts: [], warnings: []);

    XmlDocument doc;
    try {
      doc = XmlDocument.parse(input);
    } on XmlException catch (e) {
      return (hosts: [], warnings: ['Invalid XML: ${e.message}']);
    }

    final sessionsKey = doc
        .findAllElements('key')
        .where((e) => e.getAttribute('name') == 'Sessions')
        .firstOrNull;
    if (sessionsKey == null) {
      return (hosts: [], warnings: ['No Sessions key found in XML']);
    }

    final hosts = <Host>[];
    _walkKeys(sessionsKey, '', hosts);
    return (hosts: hosts, warnings: []);
  }

  void _walkKeys(XmlElement parent, String groupPath, List<Host> hosts) {
    for (final child in parent.childElements) {
      if (child.name.local != 'key') continue;
      final name = child.getAttribute('name') ?? '';

      final hostnameEl = child.childElements
          .where((e) =>
              e.name.local == 'value' &&
              e.getAttribute('name') == 'Hostname')
          .firstOrNull;

      if (hostnameEl != null) {
        final hostname = hostnameEl.innerText.trim();
        if (hostname.isEmpty) continue;

        final portEl = child.childElements
            .where((e) =>
                e.name.local == 'value' && e.getAttribute('name') == 'Port')
            .firstOrNull;
        final port = int.tryParse(portEl?.innerText.trim() ?? '') ?? 22;

        final userEl = child.childElements
            .where((e) =>
                e.name.local == 'value' &&
                e.getAttribute('name') == 'Username')
            .firstOrNull;
        final user = userEl?.innerText.trim() ?? '';

        hosts.add(Host(
          label: name,
          host: hostname,
          port: port,
          username: user,
          group: groupPath,
        ));
      } else {
        final newPath =
            groupPath.isEmpty ? name : '$groupPath/$name';
        _walkKeys(child, newPath, hosts);
      }
    }
  }
}

// ── WinSCP ────────────────────────────────────────────────

class WinScpParser extends ImportParser {
  const WinScpParser();

  static final _sectionRe = RegExp(r'^\[Sessions\\(.+)\]$');

  @override
  ParseResult parse(String input) {
    final hosts = <Host>[];
    String? currentSession;
    final props = <String, String>{};

    void flush() {
      if (currentSession == null) return;
      final hostname = props['HostName'];
      if (hostname == null || hostname.isEmpty) {
        currentSession = null;
        props.clear();
        return;
      }
      final port = int.tryParse(props['PortNumber'] ?? '') ?? 22;
      final username = props['UserName'] ?? '';

      final parts = currentSession!.split(r'\');
      final label = parts.last;
      final group = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';

      hosts.add(Host(
        label: label,
        host: hostname,
        port: port,
        username: username,
        group: group,
      ));
      currentSession = null;
      props.clear();
    }

    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final sectionMatch = _sectionRe.firstMatch(line);
      if (sectionMatch != null) {
        flush();
        final rawName = Uri.decodeComponent(sectionMatch.group(1)!.replaceAll('+', ' '));
        // Skip the root [Sessions\] entry (empty name or just whitespace)
        currentSession = rawName.trim().isEmpty ? null : rawName;
        continue;
      }

      if (currentSession == null) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      props[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }

    flush();
    return (hosts: hosts, warnings: const []);
  }
}

// ── Ansible INI Inventory ─────────────────────────────────

class AnsibleParser extends ImportParser {
  const AnsibleParser();

  static final _sectionRe = RegExp(r'^\[(.+)\]$');
  static final _varRe = RegExp(r'(\S+)=(\S+)');

  @override
  ParseResult parse(String input) {
    final hosts = <Host>[];
    final warnings = <String>[];
    String currentGroup = '';
    bool skipSection = false;

    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final sectionMatch = _sectionRe.firstMatch(line);
      if (sectionMatch != null) {
        final sectionName = sectionMatch.group(1)!;
        skipSection =
            sectionName.contains(':vars') || sectionName.contains(':children');
        if (!skipSection) currentGroup = sectionName.split(':').first;
        continue;
      }

      if (skipSection) continue;

      final tokens = line.split(RegExp(r'\s+'));
      final alias = tokens[0];
      final vars = <String, String>{};
      for (final token in tokens.skip(1)) {
        final m = _varRe.firstMatch(token);
        if (m != null) vars[m.group(1)!] = m.group(2)!;
      }

      final hostname = vars['ansible_host'] ?? alias;
      final userVal =
          vars['ansible_user'] ?? vars['ansible_ssh_user'] ?? 'root';

      int port = 22;
      final portStr = vars['ansible_port'];
      if (portStr != null) {
        final parsed = int.tryParse(portStr);
        if (parsed == null || parsed < 1 || parsed > 65535) {
          warnings.add(
              'Host "$alias": invalid ansible_port "$portStr", skipped');
          continue;
        }
        port = parsed;
      }

      hosts.add(Host(
        label: alias,
        host: hostname,
        port: port,
        username: userVal,
        group: currentGroup,
      ));
    }

    return (hosts: hosts, warnings: warnings);
  }
}

// ── Termius JSON ──────────────────────────────────────────

class TermiusParser extends ImportParser {
  const TermiusParser();

  @override
  ParseResult parse(String input) {
    if (input.trim().isEmpty) return (hosts: [], warnings: []);

    dynamic decoded;
    try {
      decoded = jsonDecode(input);
    } catch (_) {
      return (hosts: [], warnings: ['Invalid JSON']);
    }

    if (decoded is Map && decoded.containsKey('hosts')) {
      final list = decoded['hosts'];
      if (list is! List) {
        return (hosts: [], warnings: ['hosts field is not an array']);
      }
      final hosts = <Host>[];
      for (final entry in list) {
        if (entry is! Map) continue;
        final address = (entry['address'] as String?)?.trim() ?? '';
        if (address.isEmpty) continue;
        final label = (entry['label'] as String?)?.trim() ?? address;
        final port = (entry['port'] as num?)?.toInt() ?? 22;
        final username = (entry['username'] as String?)?.trim() ?? '';
        final groupMap = entry['group'];
        final group =
            groupMap is Map ? (groupMap['label'] as String?)?.trim() ?? '' : '';
        hosts.add(Host(
            label: label,
            host: address,
            port: port,
            username: username,
            group: group));
      }
      return (hosts: hosts, warnings: []);
    }

    // Fallback: try as a JSON array in YourSSH export format
    if (decoded is! List) return (hosts: [], warnings: []);
    try {
      final hosts = decoded
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final map = Map<String, dynamic>.from(e)..remove('id');
            return Host.fromJson({
              'label': map['label'] ?? '',
              'host': map['host'] ?? '',
              'port': map['port'] ?? 22,
              'username': map['username'] ?? 'root',
              'authType': map['authType'] ?? 'password',
              'group': map['group'] ?? '',
              'tags': map['tags'] ?? [],
              'createdAt': DateTime.now().toIso8601String(),
            });
          })
          .where((h) => h.host.isNotEmpty)
          .toList();
      return (hosts: hosts, warnings: []);
    } catch (_) {
      return (hosts: [], warnings: []);
    }
  }
}

// ── SSH URI ───────────────────────────────────────────────

class SshUriParser extends ImportParser {
  const SshUriParser();

  static final _uriRe = RegExp(
    r'ssh://([^@]+)@([^:/?#\s]+)(?::(\d+))?(?:[/?#][^\s]*)?$',
    caseSensitive: false,
  );

  @override
  ParseResult parse(String input) {
    final hosts = <Host>[];
    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = _uriRe.firstMatch(line);
      if (m == null) continue;
      final user = m.group(1)!;
      final host = m.group(2)!;
      final port = int.tryParse(m.group(3) ?? '') ?? 22;
      hosts.add(Host(label: '$user@$host', host: host, port: port, username: user));
    }
    return (hosts: hosts, warnings: []);
  }
}
