import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Where the app's CLI endpoint and token file live on this machine.
class CliEndpoint {
  const CliEndpoint._(this.runDir, this.address, this.tokenPath,
      {this.inSharedTemp = false});

  /// Unix socket paths must stay under sun_path (104 bytes on macOS, 108 on
  /// Linux); at or above this many bytes we use a short per-user location.
  static const int maxSocketPathBytes = 100;

  final String runDir;

  /// Unix socket path (POSIX) or named pipe name (Windows).
  final String address;
  final String tokenPath;

  /// True when the run dir is the short fallback under a temp directory. The
  /// listener must then refuse a pre-existing dir that is not ours / not 0700.
  final bool inSharedTemp;

  /// [dev] selects the endpoint of a non-release (debug/profile) app build,
  /// so a `flutter run` copy never shares the installed app's endpoint, lock
  /// or token: run dir `YourSSH-dev` (macOS, Windows) / `yourssh-dev`
  /// (Linux), short fallbacks `yourssh-dev-run` / `/tmp/yourssh-dev-<uid>`,
  /// pipe `\\.\pipe\yourssh-cli-dev-<SID>`.
  static CliEndpoint resolve({
    required String os,
    required Map<String, String> env,
    required String home,
    String? userSid,
    int? uid,
    bool dev = false,
  }) {
    final suffix = dev ? '-dev' : '';
    switch (os) {
      case 'macos':
        return _posixOrFallback(
          p.posix.join(
              home, 'Library', 'Application Support', 'YourSSH$suffix', 'run'),
          () {
            final tmp = env['TMPDIR'];
            return (tmp != null && tmp.isNotEmpty)
                ? p.posix.join(tmp, 'yourssh$suffix-run')
                : _tmpFallback(env, uid, suffix);
          },
        );
      case 'linux':
        final xdg = env['XDG_RUNTIME_DIR'];
        if (xdg != null && xdg.isNotEmpty) {
          return _posixOrFallback(p.posix.join(xdg, 'yourssh$suffix'),
              () => _tmpFallback(env, uid, suffix));
        }
        return _posixOrFallback(
            p.posix.join(home, '.local', 'state', 'yourssh$suffix', 'run'),
            () => _tmpFallback(env, uid, suffix));
      case 'windows':
        if (userSid == null || userSid.isEmpty) {
          throw ArgumentError('userSid is required on Windows');
        }
        final base = env['LOCALAPPDATA'] ?? p.windows.join(home, 'AppData', 'Local');
        final dir = p.windows.join(base, 'YourSSH$suffix', 'run');
        return CliEndpoint._(
          dir,
          r'\\.\pipe\yourssh-cli' + suffix + '-' + userSid,
          p.windows.join(dir, 'cli.token'),
        );
      default:
        throw ArgumentError('unsupported os: $os');
    }
  }

  /// The endpoint the `yourssh` binary talks to: home from `HOME`
  /// (`USERPROFILE` on Windows), and the dev variant when `YOURSSH_DEV=1`
  /// (to reach an app started with `flutter run`).
  static CliEndpoint forCli({
    required String os,
    required Map<String, String> env,
    int? uid,
    String? userSid,
  }) =>
      resolve(
        os: os,
        env: env,
        home: (os == 'windows' ? env['USERPROFILE'] : env['HOME']) ?? '',
        uid: uid,
        userSid: userSid,
        dev: isDevEnv(env),
      );

  /// `YOURSSH_DEV=1`: talk to a non-release app build.
  static bool isDevEnv(Map<String, String> env) => env['YOURSSH_DEV'] == '1';

  static String _tmpFallback(
          Map<String, String> env, int? uid, String suffix) =>
      '/tmp/yourssh$suffix-${uid ?? env['USER'] ?? 'user'}';

  static CliEndpoint _posixOrFallback(
      String dir, String Function() fallbackDir) {
    final sock = p.posix.join(dir, 'cli.sock');
    if (utf8.encode(sock).length < maxSocketPathBytes) return _posix(dir);
    final fb = fallbackDir();
    return CliEndpoint._(
      fb,
      p.posix.join(fb, 'cli.sock'),
      p.posix.join(fb, 'cli.token'),
      inSharedTemp: true,
    );
  }

  static CliEndpoint _posix(String dir) => CliEndpoint._(
        dir,
        p.posix.join(dir, 'cli.sock'),
        p.posix.join(dir, 'cli.token'),
      );
}

Future<void> _chmod(String mode, String path) async {
  if (Platform.isWindows) return;
  final r = await Process.run('/bin/chmod', [mode, path]);
  if (r.exitCode != 0) {
    throw FileSystemException('chmod $mode failed: ${r.stderr}', path);
  }
}

/// 32 random bytes as lowercase hex.
String generateToken() {
  final rng = Random.secure();
  return List.generate(32, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Creates [runDir] (0700) and rewrites `cli.token` (0600) with 32 random
/// bytes as lowercase hex. The file is created empty and restricted before
/// the secret is written. On Windows (per-user %LOCALAPPDATA%, no modes) it
/// is truncated and overwritten in place. Returns the token.
Future<String> writeToken(String runDir, {String? token}) async {
  final dir = Directory(runDir);
  await dir.create(recursive: true);
  await _chmod('700', runDir);

  token ??= generateToken();

  final path = p.join(runDir, 'cli.token');
  final file = File(path);
  if (Platform.isWindows) {
    // Truncate and overwrite in place: deleting a file another process has
    // open fails or lingers on Windows. %LOCALAPPDATA% is per user.
    await file.writeAsString(token, flush: true);
    return token;
  }
  if (await file.exists()) await file.delete();
  await file.create();
  await _chmod('600', path);
  await file.writeAsString(token, flush: true);
  return token;
}

/// The stored token, or null when the file is missing or unreadable.
Future<String?> readToken(String tokenPath) async {
  try {
    final s = (await File(tokenPath).readAsString()).trim();
    return s.isEmpty ? null : s;
  } on FileSystemException {
    return null;
  }
}

/// Like [readToken] but only a missing file yields null (also an empty one);
/// any other failure (EACCES, a directory, ...) is rethrown so the caller can
/// tell "not there yet" from "cannot read".
Future<String?> readTokenStrict(String tokenPath) async {
  try {
    final s = (await File(tokenPath).readAsString()).trim();
    return s.isEmpty ? null : s;
  } on PathNotFoundException {
    return null;
  }
}

/// Constant-time comparison (length is not secret).
bool tokensEqual(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
