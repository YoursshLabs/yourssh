import 'dart:convert';

/// Removes C0/C1 control characters (incl. ESC, DEL, CR/LF, tab) from a
/// server-provided string so it cannot inject terminal escapes.
String sanitize(Object? s) {
  final str = s?.toString() ?? '';
  final b = StringBuffer();
  for (final r in str.runes) {
    if (r < 0x20 || (r >= 0x7f && r <= 0x9f)) continue;
    b.writeCharCode(r);
  }
  return b.toString();
}

/// `user@host:port` for a host summary map (sanitized).
String hostAddress(Map<String, Object?> h) {
  final user = sanitize(h['username']);
  final host = sanitize(h['host']);
  final port = sanitize(h['port']);
  return '${user.isEmpty ? '' : '$user@'}$host${port.isEmpty ? '' : ':$port'}';
}

/// Renders the `ls` table. [color] adds a bold header only.
String renderHostTable(List<Object?> hosts, {required bool color}) {
  final rows = <List<String>>[
    ['LABEL', 'USER@HOST:PORT', 'PROTOCOL', 'TAGS'],
  ];
  for (final h in hosts) {
    if (h is! Map<String, Object?>) continue;
    final tags = h['tags'];
    rows.add([
      sanitize(h['label']),
      hostAddress(h),
      sanitize(h['protocol']),
      tags is List ? tags.map(sanitize).join(',') : '',
    ]);
  }
  final widths = List<int>.filled(4, 0);
  for (final r in rows) {
    for (var i = 0; i < 4; i++) {
      if (r[i].length > widths[i]) widths[i] = r[i].length;
    }
  }
  final b = StringBuffer();
  for (var n = 0; n < rows.length; n++) {
    final r = rows[n];
    final cells = [
      for (var i = 0; i < 4; i++) i == 3 ? r[i] : r[i].padRight(widths[i]),
    ];
    final line = cells.join('  ').trimRight();
    b.writeln(color && n == 0 ? '\x1b[1m$line\x1b[0m' : line);
  }
  return b.toString();
}

/// `ls --json` output. jsonEncode escapes C0 controls but leaves DEL and
/// C1 (U+007F–U+009F) raw, and some terminals act on C1; escape them too.
/// They can only occur inside strings, so the result is the same JSON value.
String jsonHosts(List<Object?> hosts) => escapeJsonC1(jsonEncode(hosts));

/// Replaces U+007F–U+009F in encoded JSON with `\u00XX` escapes.
String escapeJsonC1(String json) {
  final b = StringBuffer();
  for (final r in json.runes) {
    if (r >= 0x7f && r <= 0x9f) {
      b.write('\\u00${r.toRadixString(16)}');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}
