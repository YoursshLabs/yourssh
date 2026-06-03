import 'package:yourssh/models/app_release.dart';

/// Network + platform glue for the in-app update flow.
/// Pure helpers (`isNewerVersion`, `assetForPlatform`) are unit-tested;
/// IO methods (`fetchLatestRelease`, `downloadAsset`, `launchInstaller`)
/// are added in later tasks.
class UpdateService {
  UpdateService();

  static final RegExp _versionSuffix = RegExp(r'[-+]');

  /// Returns true when [latest] is a strictly higher semantic version than
  /// [current]. Leading `v` and any `-pre`/`+build` suffix are ignored.
  /// Fails closed: unparseable [current] or [latest] never reports "newer"
  /// unless the parsed numbers genuinely differ.
  bool isNewerVersion(String current, String latest) {
    // Fail closed: an unknown/blank current version must never prompt an update.
    if (current.trim().isEmpty) return false;
    final a = _parse(current);
    final b = _parse(latest);
    for (var i = 0; i < 3; i++) {
      if (b[i] > a[i]) return true;
      if (b[i] < a[i]) return false;
    }
    return false;
  }

  /// Parses `major.minor.patch` into a 3-int list. Strips a leading `v` and
  /// drops anything from the first `-` or `+`. Missing/garbage segments -> 0.
  List<int> _parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final cut = s.indexOf(_versionSuffix);
    if (cut != -1) s = s.substring(0, cut);
    final parts = s.split('.');
    final out = <int>[0, 0, 0];
    for (var i = 0; i < 3 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }
}
