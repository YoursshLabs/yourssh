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

  static CliEndpoint resolve({
    required String os,
    required Map<String, String> env,
    required String home,
    String? userSid,
    int? uid,
  }) {
    switch (os) {
      case 'macos':
        return _posixOrFallback(
          p.posix.join(home, 'Library', 'Application Support', 'YourSSH', 'run'),
          () {
            final tmp = env['TMPDIR'];
            return (tmp != null && tmp.isNotEmpty)
                ? p.posix.join(tmp, 'yourssh-run')
                : _tmpFallback(env, uid);
          },
        );
      case 'linux':
        final xdg = env['XDG_RUNTIME_DIR'];
        if (xdg != null && xdg.isNotEmpty) {
          return _posixOrFallback(
              p.posix.join(xdg, 'yourssh'), () => _tmpFallback(env, uid));
        }
        return _posixOrFallback(
            p.posix.join(home, '.local', 'state', 'yourssh', 'run'),
            () => _tmpFallback(env, uid));
      case 'windows':
        if (userSid == null || userSid.isEmpty) {
          throw ArgumentError('userSid is required on Windows');
        }
        final base = env['LOCALAPPDATA'] ?? p.windows.join(home, 'AppData', 'Local');
        final dir = p.windows.join(base, 'YourSSH', 'run');
        return CliEndpoint._(
          dir,
          r'\\.\pipe\yourssh-cli-' + userSid,
          p.windows.join(dir, 'cli.token'),
        );
      default:
        throw ArgumentError('unsupported os: $os');
    }
  }

  static String _tmpFallback(Map<String, String> env, int? uid) =>
      '/tmp/yourssh-${uid ?? env['USER'] ?? 'user'}';

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

/// Creates [runDir] (0700) and rewrites `cli.token` (0600) with 32 random
/// bytes as lowercase hex. The file is created empty and restricted before
/// the secret is written. Returns the token.
Future<String> writeToken(String runDir) async {
  final dir = Directory(runDir);
  await dir.create(recursive: true);
  await _chmod('700', runDir);

  final rng = Random.secure();
  final token = List.generate(32, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  final path = p.join(runDir, 'cli.token');
  final file = File(path);
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

/// Constant-time comparison (length is not secret).
bool tokensEqual(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
