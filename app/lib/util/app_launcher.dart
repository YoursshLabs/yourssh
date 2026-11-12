// app/lib/util/app_launcher.dart
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// Opens [filePath] with the OS default application.
Future<bool> launchFileDefault(String filePath) =>
    launchUrl(Uri.file(filePath));

const _windowsExecutableExts = {
  'exe', 'bat', 'cmd', 'com', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'wsf',
  'wsh', 'hta', 'msi', 'msp', 'lnk', 'scr', 'reg', 'cpl', 'pif', 'url',
  'appref-ms',
};
const _macosExecutableExts = {
  'app', 'command', 'tool', 'pkg', 'mpkg', 'terminal', 'workflow', 'scpt',
  'jar',
};
const _linuxExecutableExts = {
  'desktop', 'sh', 'run', 'appimage', 'jar',
};

/// Whether the OS default handler would execute [name] rather than display
/// it. [platform] is a `Platform.operatingSystem` value ('windows', 'macos',
/// 'linux'); it is a parameter so the check is testable on any host.
bool isExecutableExtension(String name, String platform) {
  var n = name;
  // Windows silently drops trailing dots and spaces, so `a.exe.` runs.
  if (platform == 'windows') n = n.replaceAll(RegExp(r'[. ]+$'), '');
  final dot = n.lastIndexOf('.');
  if (dot <= 0) return false; // no extension, or a dotfile like .bashrc
  final ext = n.substring(dot + 1).toLowerCase();
  switch (platform) {
    case 'windows':
      return _windowsExecutableExts.contains(ext);
    case 'macos':
      return _macosExecutableExts.contains(ext);
    case 'linux':
      return _linuxExecutableExts.contains(ext);
  }
  return false;
}

/// A process invocation, separated from [Process.run] so it can be tested.
class AppLaunchSpec {
  const AppLaunchSpec(this.executable, this.arguments,
      {this.runInShell = false});
  final String executable;
  final List<String> arguments;
  final bool runInShell;
}

/// Builds the invocation that opens [filePath] with [appPath]. Never uses a
/// shell: [filePath] may be named by a remote server and must not reach
/// cmd.exe metacharacter parsing.
AppLaunchSpec buildAppLaunch({
  required String platform,
  required String filePath,
  required String appPath,
}) {
  if (platform == 'macos') {
    return AppLaunchSpec('open', ['-a', appPath, filePath]);
  }
  return AppLaunchSpec(appPath, [filePath]);
}

/// Opens [filePath] with a specific application (`open -a` on macOS, direct
/// process spawn elsewhere). Extracted from ExternalEditService.
Future<bool> launchFileWithApp(String filePath, String appPath) {
  final spec = buildAppLaunch(
      platform: Platform.operatingSystem,
      filePath: filePath,
      appPath: appPath);
  return Process.run(spec.executable, spec.arguments,
          runInShell: spec.runInShell)
      .then((r) => r.exitCode == 0);
}

/// Lets the user pick an application bundle/executable (per-platform
/// filters). Extracted from SftpPanel._pickApp.
Future<String?> pickApplication() async {
  if (Platform.isMacOS) {
    const typeGroup = XTypeGroup(label: 'Applications', extensions: ['app']);
    final file = await openFile(
        acceptedTypeGroups: [typeGroup], initialDirectory: '/Applications');
    return file?.path;
  }
  if (Platform.isWindows) {
    const typeGroup = XTypeGroup(label: 'Executables', extensions: ['exe']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    return file?.path;
  }
  final file = await openFile();
  return file?.path;
}
