// app/test/providers/settings_provider_shell_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/shell_profile.dart';
import 'package:yourssh/providers/settings_provider.dart';

/// SettingsProvider kicks off _load() in its constructor; give the async
/// prefs read a microtask turn before asserting.
Future<SettingsProvider> loadedProvider() async {
  final p = SettingsProvider();
  await Future<void>.delayed(Duration.zero);
  return p;
}

const _nu = ShellProfile(
  id: 'custom-1',
  name: 'Nu',
  executable: '/usr/bin/nu',
  args: ['-l'],
  isCustom: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('custom shell profiles persist across provider instances', () async {
    final p1 = await loadedProvider();
    await p1.addCustomShellProfile(_nu);
    final p2 = await loadedProvider();
    expect(p2.customShellProfiles, hasLength(1));
    expect(p2.customShellProfiles.first.name, 'Nu');
    expect(p2.customShellProfiles.first.args, ['-l']);
  });

  test('setDefaultShellId persists; null clears it', () async {
    final p1 = await loadedProvider();
    await p1.setDefaultShellId('git-bash');
    expect((await loadedProvider()).defaultShellId, 'git-bash');
    await p1.setDefaultShellId(null);
    expect((await loadedProvider()).defaultShellId, isNull);
  });

  test('removing the default custom shell resets defaultShellId', () async {
    final p = await loadedProvider();
    await p.addCustomShellProfile(_nu);
    await p.setDefaultShellId('custom-1');
    await p.removeCustomShellProfile('custom-1');
    expect(p.defaultShellId, isNull);
    expect((await loadedProvider()).defaultShellId, isNull);
  });

  test('resolveDefaultShell flags a dangling id', () async {
    final p = await loadedProvider();
    await p.setDefaultShellId('wsl-Gone');
    final r = p.resolveDefaultShell();
    expect(r.profile, isNull);
    expect(r.dangling, true);
  });

  test('allShellProfiles = detected + custom', () async {
    final p = await loadedProvider();
    p.setDetectedShells(const [
      ShellProfile(
          id: 'powershell',
          name: 'PowerShell',
          executable: 'powershell.exe'),
    ]);
    await p.addCustomShellProfile(_nu);
    expect(p.allShellProfiles.map((s) => s.id), ['powershell', 'custom-1']);
  });

  test('malformed customShellProfiles JSON keeps defaults', () async {
    SharedPreferences.setMockInitialValues({'customShellProfiles': 'not-json'});
    final p = await loadedProvider();
    expect(p.customShellProfiles, isEmpty);
  });
}
