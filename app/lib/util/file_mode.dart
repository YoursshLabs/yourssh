// app/lib/util/file_mode.dart
import 'dart:io';

/// POSIX permission-bit helpers shared by the permissions dialog and the
/// local/remote chmod paths. Only the low 12 bits (0o7777: rwx for
/// owner/group/others plus setuid/setgid/sticky) are considered.

/// Formats the permission bits of [mode] as an octal string, e.g. 0o755 ->
/// '755', 0o4755 -> '4755'. File-type bits (above 0o7777) are masked off.
String modeToOctal(int mode) =>
    (mode & 0xFFF).toRadixString(8).padLeft(3, '0');

/// Parses a 3- or 4-digit octal permission string ('644', '0755', '4755')
/// into permission bits. Returns null when [text] is not valid octal or is
/// shorter than 3 digits — a 1–2 digit value is almost always a partially
/// typed mode ('64' is 0o064, not 0o644), and applying it would silently
/// strip permissions.
int? parseOctal(String text) {
  final t = text.trim();
  if (t.length < 3 || t.length > 4) return null;
  final value = int.tryParse(t, radix: 8);
  if (value == null || value < 0 || value > 0xFFF) return null;
  return value;
}

/// POSIX permission bits, one per rwx flag. Single app-side source for the
/// permissions dialog's checkbox grid (mirrors the values dartssh2's
/// `SftpFileMode` getters encode).
const int kModeUserRead = 0x100;
const int kModeUserWrite = 0x80;
const int kModeUserExecute = 0x40;
const int kModeGroupRead = 0x20;
const int kModeGroupWrite = 0x10;
const int kModeGroupExecute = 0x8;
const int kModeOtherRead = 0x4;
const int kModeOtherWrite = 0x2;
const int kModeOtherExecute = 0x1;

/// Applies [mode] to a local [path] via the system `chmod` (macOS/Linux
/// only — the caller hides the menu item on Windows).
Future<void> chmodLocal(String path, int mode,
    {bool recursive = false}) async {
  final result = await Process.run('chmod', [
    if (recursive) '-R',
    modeToOctal(mode),
    path,
  ]);
  if (result.exitCode != 0) {
    throw Exception('chmod failed: ${result.stderr}');
  }
}
