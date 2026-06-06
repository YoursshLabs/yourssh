// app/test/models/shell_profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/shell_profile.dart';

void main() {
  group('ShellProfile JSON', () {
    test('round-trips all fields', () {
      const profile = ShellProfile(
        id: 'custom-abc',
        name: 'Nushell',
        executable: '/usr/local/bin/nu',
        args: ['-l', '--config', 'x'],
        isCustom: true,
      );
      final back = ShellProfile.fromJson(profile.toJson());
      expect(back.id, 'custom-abc');
      expect(back.name, 'Nushell');
      expect(back.executable, '/usr/local/bin/nu');
      expect(back.args, ['-l', '--config', 'x']);
      expect(back.isCustom, true);
    });

    test('fromJson defaults args/isCustom when missing', () {
      final p = ShellProfile.fromJson({
        'id': 'cmd', 'name': 'Command Prompt', 'executable': 'cmd.exe',
      });
      expect(p.args, isEmpty);
      expect(p.isCustom, false);
    });
  });

  group('resolveShellProfile', () {
    const gitBash = ShellProfile(
        id: 'git-bash', name: 'Git Bash', executable: 'bash.exe');

    test('null id means platform default, not dangling', () {
      final r = resolveShellProfile([gitBash], null);
      expect(r.profile, isNull);
      expect(r.dangling, false);
    });

    test('matching id returns the profile', () {
      final r = resolveShellProfile([gitBash], 'git-bash');
      expect(r.profile, same(gitBash));
      expect(r.dangling, false);
    });

    test('dangling id falls back to null profile and flags it', () {
      final r = resolveShellProfile([gitBash], 'wsl-Ubuntu');
      expect(r.profile, isNull);
      expect(r.dangling, true);
    });
  });
}
