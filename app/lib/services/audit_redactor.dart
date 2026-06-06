/// Pure secret masking for audit-log commands. Patterns mask only the
/// secret portion ([kMask]) so the command stays readable. No IO.
class AuditRedactor {
  static const kMask = '[REDACTED]';

  // key=value style: password=, passwd=, token=, secret=, api_key=,
  // apikey=, and prefixed forms (PGPASSWORD=, GITHUB_TOKEN=, …).
  static final _kv = RegExp(
      r'([\w-]*(?:password|passwd|token|secret|api[_-]?key)\s*=\s*)(\S+)',
      caseSensitive: false);
  static final _bearer = RegExp(
      r'(authorization:\s*bearer\s+)([^\s'
      "'"
      r'"]+)',
      caseSensitive: false);
  static final _sshpass =
      RegExp(r'(\bsshpass\s+-p\s+)(\S+)', caseSensitive: false);
  // mysql/mariadb attached password (-psecret). psql's -p is the port —
  // excluded; PGPASSWORD= is caught by _kv.
  static final _mysqlP = RegExp(r'(\b(?:mysql|mariadb)\b[^\n]*?\s-p)(\S+)');
  static final _urlCred = RegExp(r'(\w+://[^/\s:@]+:)([^@\s]+)(?=@)');

  static String redact(String command) {
    var out = command;
    out = out.replaceAllMapped(_kv, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_bearer, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_sshpass, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_mysqlP, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_urlCred, (m) => '${m[1]}$kMask');
    return out;
  }
}
