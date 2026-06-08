import 'dart:convert';
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
