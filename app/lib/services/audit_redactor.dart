/// Pure secret masking for audit-log commands. Patterns mask only the
/// secret portion ([kMask]) so the command stays readable. No IO.
class AuditRedactor {
  static const kMask = '[REDACTED]';

  /// A secret value: an already-masked token (keeps redaction idempotent),
  /// a quoted string (multi-word secrets must not leak their tail), or a
  /// bare token.
  static const _value = '''(?:\\[REDACTED\\]|"[^"]*"|'[^']*'|\\S+)''';

  static const _keys = r'[\w-]*(?:password|passwd|token|secret|api[_-]?key)';

  // key=value inside a fully quoted shell arg ('password=multi word…') —
  // masks up to the closing quote so a spaced value can't leak a tail.
  static final _kvQuotedArg = RegExp(
      '(["\'])($_keys\\s*=\\s*)[^"\']*\\1',
      caseSensitive: false);
  // key=value style: password=, passwd=, token=, secret=, api_key=,
  // and prefixed forms (PGPASSWORD=, GITHUB_TOKEN=, …).
  static final _kv =
      RegExp('($_keys\\s*=\\s*)$_value', caseSensitive: false);
  static final _bearer = RegExp(
      r'(authorization:\s*bearer\s+)([^\s'
      "'"
      r'"]+)',
      caseSensitive: false);
  static final _sshpass =
      RegExp('(\\bsshpass\\s+-p\\s+)$_value', caseSensitive: false);
  // mysql/mariadb family (incl. mysqldump/mysqladmin/mariadb-dump) attached
  // password (-psecret). psql's -p is the port — excluded; PGPASSWORD= is
  // caught by _kv. A spaced `-p <arg>` never matches: that's a database
  // name (mysql) or a port (psql), not a password.
  static final _mysqlP =
      RegExp('(\\b(?:mysql|mariadb)[\\w-]*\\b[^\\n]*?\\s-p)$_value');
  static final _redisAuth =
      RegExp('(\\bredis-cli\\b[^\\n]*?\\s-a\\s+)$_value', caseSensitive: false);
  // URL userinfo password; username may be empty (redis://:pass@host).
  static final _urlCred = RegExp(r'(\w+://[^/\s:@]*:)([^@\s]+)(?=@)');

  static String redact(String command) {
    var out = command;
    out = out.replaceAllMapped(_kvQuotedArg, (m) => '${m[1]}${m[2]}$kMask${m[1]}');
    out = out.replaceAllMapped(_kv, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_bearer, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_sshpass, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_mysqlP, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_redisAuth, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_urlCred, (m) => '${m[1]}$kMask');
    return out;
  }
}
