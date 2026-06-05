// app/lib/util/app_launcher.dart
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// Opens [filePath] with the OS default application.
Future<bool> launchFileDefault(String filePath) =>
    launchUrl(Uri.file(filePath));

/// Opens [filePath] with a specific application (`open -a` on macOS, direct
/// process spawn elsewhere). Extracted from ExternalEditService.
Future<bool> launchFileWithApp(String filePath, String appPath) {
  if (Platform.isMacOS) {
    return Process.run('open', ['-a', appPath, filePath])
        .then((r) => r.exitCode == 0);
  }
  if (Platform.isWindows) {
    return Process.run(appPath, [filePath], runInShell: true)
        .then((r) => r.exitCode == 0);
  }
  return Process.run(appPath, [filePath]).then((r) => r.exitCode == 0);
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
