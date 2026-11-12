import 'package:path/path.dart' as p;

/// Thrown when a server-controlled name would escape the local directory it
/// is meant to be written into.
class UnsafeRemotePathException implements Exception {
  final String name;
  UnsafeRemotePathException(this.name);

  @override
  String toString() => 'Unsafe remote file name refused: "$name"';
}

/// True when [name] is a single, plain path component that is safe to use as
/// a local file name. Remote servers control these names, so anything that
/// could navigate (`.`, `..`, separators of either OS) or is a control
/// character (including NUL) is rejected.
bool isSafeRemoteEntryName(String name) {
  if (name.isEmpty || name == '.' || name == '..') return false;
  for (final unit in name.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return false;
    if (unit == 0x2f /* / */ || unit == 0x5c /* \ */) return false;
  }
  return true;
}

/// Joins [name] onto [dir] after validating it, and verifies the result is
/// still strictly inside [dir]. Throws [UnsafeRemotePathException] otherwise.
String safeLocalChild(String dir, String name) {
  if (!isSafeRemoteEntryName(name)) throw UnsafeRemotePathException(name);
  final joined = p.join(dir, name);
  if (!p.isWithin(p.normalize(dir), p.normalize(joined))) {
    throw UnsafeRemotePathException(name);
  }
  return joined;
}
