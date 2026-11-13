import 'dart:convert';

const int kCliProtocolVersion = 1;
const int kMaxRequestBytes = 64 * 1024;

/// Cap on a response line (an `ls` answer can be large; requests stay at 64 KiB).
const int kMaxResponseBytes = 16 * 1024 * 1024;

/// Process exit codes of the `yourssh` executable (also carried in responses).
enum CliExit {
  ok(0),
  runtime(1),
  usage(2),
  unreachable(3),
  denied(4);

  const CliExit(this.code);
  final int code;

  static CliExit? fromCode(int code) {
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }
}

class CliProtocolException implements Exception {
  CliProtocolException(this.code, this.message);
  final CliExit code;
  final String message;

  @override
  String toString() => 'CliProtocolException(${code.name}): $message';
}

const Set<String> kCliCommands = {
  'connect',
  'ls',
  'version',
  'open',
  'activate',
};

Map<String, Object?> _decodeObject(String line, int maxBytes) {
  if (utf8.encode(line).length > maxBytes) {
    throw CliProtocolException(CliExit.usage, 'line too long');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    throw CliProtocolException(CliExit.usage, 'invalid JSON');
  }
  if (decoded is! Map<String, Object?>) {
    throw CliProtocolException(CliExit.usage, 'expected a JSON object');
  }
  final v = decoded['v'];
  if (v != kCliProtocolVersion) {
    throw CliProtocolException(
        CliExit.unreachable, 'unsupported protocol version: $v');
  }
  return decoded;
}

void _checkKeys(Map<String, Object?> m, Set<String> required, Set<String> optional) {
  for (final k in required) {
    if (!m.containsKey(k)) {
      throw CliProtocolException(CliExit.usage, 'missing field: $k');
    }
  }
  for (final k in m.keys) {
    if (!required.contains(k) && !optional.contains(k)) {
      throw CliProtocolException(CliExit.usage, 'unknown field: $k');
    }
  }
}

class CliRequest {
  const CliRequest({
    required this.id,
    required this.token,
    required this.cmd,
    required this.args,
  });

  final String id;
  final String token;
  final String cmd;
  final Map<String, Object?> args;

  String encode() => jsonEncode({
        'v': kCliProtocolVersion,
        'id': id,
        'token': token,
        'cmd': cmd,
        'args': args,
      });

  static CliRequest decode(String line) {
    final m = _decodeObject(line, kMaxRequestBytes);
    _checkKeys(m, {'v', 'id', 'token', 'cmd', 'args'}, const {});
    final id = m['id'];
    final token = m['token'];
    final cmd = m['cmd'];
    final args = m['args'];
    if (id is! String || token is! String || cmd is! String) {
      throw CliProtocolException(CliExit.usage, 'id, token, cmd must be strings');
    }
    if (args is! Map<String, Object?>) {
      throw CliProtocolException(CliExit.usage, 'args must be an object');
    }
    return CliRequest(id: id, token: token, cmd: cmd, args: args);
  }
}

class CliResponse {
  const CliResponse._({
    required this.id,
    required this.ok,
    this.result,
    this.code,
    this.error,
    this.candidates,
  });

  factory CliResponse.success(String id, Object? result) =>
      CliResponse._(id: id, ok: true, result: result);

  factory CliResponse.failure(
    String id,
    CliExit code,
    String error, {
    List<Map<String, Object?>>? candidates,
  }) =>
      CliResponse._(
        id: id,
        ok: false,
        code: code,
        error: error,
        candidates: candidates,
      );

  final String id;
  final bool ok;
  final Object? result;
  final CliExit? code;
  final String? error;
  final List<Map<String, Object?>>? candidates;

  String encode() {
    final m = <String, Object?>{
      'v': kCliProtocolVersion,
      'id': id,
      'ok': ok,
    };
    if (ok) {
      m['result'] = result;
    } else {
      m['code'] = (code ?? CliExit.runtime).code;
      m['error'] = error ?? '';
      if (candidates != null) m['candidates'] = candidates;
    }
    return jsonEncode(m);
  }

  static CliResponse decode(String line) {
    final m = _decodeObject(line, kMaxResponseBytes);
    final ok = m['ok'];
    final id = m['id'];
    if (ok is! bool || id is! String) {
      throw CliProtocolException(CliExit.usage, 'invalid response');
    }
    if (ok) {
      _checkKeys(m, {'v', 'id', 'ok', 'result'}, const {});
      return CliResponse.success(id, m['result']);
    }
    _checkKeys(m, {'v', 'id', 'ok', 'code', 'error'}, {'candidates'});
    final codeRaw = m['code'];
    final error = m['error'];
    final code = codeRaw is int ? CliExit.fromCode(codeRaw) : null;
    if (code == null || error is! String) {
      throw CliProtocolException(CliExit.usage, 'invalid failure response');
    }
    List<Map<String, Object?>>? candidates;
    final c = m['candidates'];
    if (c != null) {
      if (c is! List || c.any((e) => e is! Map<String, Object?>)) {
        throw CliProtocolException(CliExit.usage, 'invalid candidates');
      }
      candidates = c.cast<Map<String, Object?>>();
    }
    return CliResponse.failure(id, code, error, candidates: candidates);
  }
}

void _usage(String msg) => throw CliProtocolException(CliExit.usage, msg);

void _allowOnly(String cmd, Map<String, Object?> args, Set<String> allowed) {
  for (final k in args.keys) {
    if (!allowed.contains(k)) _usage('$cmd: unknown argument: $k');
  }
}

void _optString(String cmd, Map<String, Object?> args, String key) {
  final v = args[key];
  if (v != null && v is! String) _usage('$cmd: $key must be a string');
}

/// Validates `args` for `cmd`; throws [CliProtocolException] (usage) otherwise.
void validateArgs(String cmd, Map<String, Object?> args) {
  switch (cmd) {
    case 'connect':
      _allowOnly(cmd, args, {'host'});
      if (args['host'] is! String) _usage('connect: host must be a string');
    case 'open':
      _allowOnly(cmd, args, {'url'});
      if (args['url'] is! String) _usage('open: url must be a string');
    case 'ls':
      _allowOnly(cmd, args, {'tag', 'filter'});
      _optString(cmd, args, 'tag');
      _optString(cmd, args, 'filter');
    case 'version':
    case 'activate':
      _allowOnly(cmd, args, const {});
    default:
      _usage('unknown command: $cmd');
  }
}
