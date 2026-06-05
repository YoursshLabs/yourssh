/// Pure helpers for distro-level OS detection and OS icon assets.
/// No Flutter/IO imports — fully unit-testable.
library;

/// detectedOs values that have a matching `assets/os/<key>.svg`.
/// Raw distro ids must go through [normalizeDistroId] first — aliases like
/// `amzn` are not keys.
const Set<String> kOsIconKeys = {
  'linux', 'macos', 'windows',
  'ubuntu', 'debian', 'fedora', 'centos', 'rocky', 'alma',
  'alpine', 'amazon', 'arch', 'suse', 'redhat',
};

const Map<String, String> _distroAliases = {
  'amzn': 'amazon',
  'almalinux': 'alma',
  'rhel': 'redhat',
  'raspbian': 'debian',
  'sles': 'suse',
};

/// Extracts the `ID=` value from `/etc/os-release` content
/// (e.g. `ubuntu`, `"rocky"`, `'alpine'`). Returns null when absent.
String? parseOsReleaseId(String content) {
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (!t.startsWith('ID=')) continue;
    var v = t.substring(3).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v.isEmpty ? null : v.toLowerCase();
  }
  return null;
}

/// Maps an os-release ID to an icon key in [kOsIconKeys].
/// Unknown distros fall back to generic `linux`.
String normalizeDistroId(String id) {
  final lower = id.toLowerCase();
  if (kOsIconKeys.contains(lower)) return lower;
  final alias = _distroAliases[lower];
  if (alias != null) return alias;
  if (lower.startsWith('opensuse')) return 'suse';
  return 'linux';
}

/// Asset path for a detectedOs value, or null when no icon ships for it
/// (callers keep their generic fallback, e.g. `Icons.dns`).
String? osIconAsset(String? detectedOs) =>
    detectedOs != null && kOsIconKeys.contains(detectedOs)
        ? 'assets/os/$detectedOs.svg'
        : null;
