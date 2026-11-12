import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Where the app's CLI endpoint and token file live on this machine.
class CliEndpoint {
  const CliEndpoint._(this.runDir, this.address, this.tokenPath);

  final String runDir;

  /// Unix socket path (POSIX) or named pipe name (Windows).
  final String address;
  final String tokenPath;

  static CliEndpoint resolve({
    required String os,
    required Map<String, String> env,
    required String home,
    String? userSid,
  }) {
    switch (os) {
      case 'macos':
        return _posix(p.posix
            .join(home, 'Library', 'Application Support', 'YourSSH', 'run'));
      case 'linux':
        final xdg = env['XDG_RUNTIME_DIR'];
        if (xdg != null && xdg.isNotEmpty) {
          return _posix(p.posix.join(xdg, 'yourssh'));
        }
        return _posix(p.posix.join(home, '.local', 'state', 'yourssh', 'run'));
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

  static CliEndpoint _posix(String dir) => CliEndpoint._(
        dir,
        p.posix.join(dir, 'cli.sock'),
        p.posix.join(dir, 'cli.token'),
      );
}

Future<void> _chmod(String mode, String path) async {
  if (Platform.isWindows) return;
  final r = await Process.run('chmod', [mode, path]);
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
