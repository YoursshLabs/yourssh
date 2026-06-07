// app/lib/models/shell_profile.dart
//
// One launchable local shell: detected (PowerShell, Git Bash, a WSL distro,
// an /etc/shells entry) or user-added custom. Detected profiles are
// re-detected every launch and never persisted; their ids are stable so the
// saved defaultShellId keeps pointing at them. Only custom profiles
// serialize to prefs.

/// Sentinel id meaning "no profile — use the platform default shell" in UI
/// pickers (Settings dropdown, new-tab menu). Never collides with real
/// profile ids ('powershell', 'wsl-…', 'etc-/…', `custom-<uuid>`).
const kPlatformDefaultShellId = '__platform_default__';

class ShellProfile {
  final String id;
  final String name;
  final String executable;
  final List<String> args;
  final bool isCustom;

  const ShellProfile({
    required this.id,
    required this.name,
    required this.executable,
    this.args = const [],
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'executable': executable,
        'args': args,
        'isCustom': isCustom,
      };

  factory ShellProfile.fromJson(Map<String, dynamic> json) => ShellProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        executable: json['executable'] as String,
        args: (json['args'] as List<dynamic>? ?? const [])
            .map((a) => a as String)
            .toList(),
        isCustom: json['isCustom'] as bool? ?? false,
      );
}

/// Result of resolving the configured default shell. [dangling] is true when
/// a non-null defaultShellId no longer matches any profile (the shell was
/// uninstalled) — callers fall back to the platform default and surface a
/// warning instead of erroring.
typedef ShellResolution = ({ShellProfile? profile, bool dangling});

ShellResolution resolveShellProfile(
  List<ShellProfile> profiles,
  String? defaultShellId,
) {
  if (defaultShellId == null) return (profile: null, dangling: false);
  for (final p in profiles) {
    if (p.id == defaultShellId) return (profile: p, dangling: false);
  }
  return (profile: null, dangling: true);
}
