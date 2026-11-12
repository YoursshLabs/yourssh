import 'dart:io';

final _driveLetter = RegExp(r'^[A-Za-z]:');

/// Resolves [relative] inside [pluginDir] and returns the file, or `null` when
/// the file does not exist or resolves (after following symlinks) outside the
/// plugin directory. Absolute paths and `..` escapes are rejected.
File? resolvePluginFile(String pluginDir, String relative) {
  if (relative.isEmpty ||
      relative.startsWith('/') ||
      relative.startsWith(r'\') ||
      _driveLetter.hasMatch(relative)) {
    return null;
  }
  try {
    final base = Directory(pluginDir).resolveSymbolicLinksSync();
    final candidate = File('$base${Platform.pathSeparator}$relative');
    if (!candidate.existsSync()) return null;
    final resolved = candidate.resolveSymbolicLinksSync();
    final prefix = base.endsWith(Platform.pathSeparator)
        ? base
        : '$base${Platform.pathSeparator}';
    if (!resolved.startsWith(prefix)) return null;
    return File(resolved);
  } on FileSystemException {
    return null;
  }
}
