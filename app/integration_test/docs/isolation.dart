// Isolation for the docs screenshot harness: nothing may reach the owner's
// real prefs plist, Keychain, ~/.yourssh, ~/Documents/YourSSH or audit db.
//
//  * SharedPreferences  -> in-memory (setMockInitialValues)
//  * FlutterSecureStorage -> in-memory (setMockInitialValues)
//  * path_provider      -> directories under the run's temp root
//  * HOME-based paths   -> the process is launched with HOME=<demoHome> (see
//    tool/docs_journey.sh); [assertIsolatedHome] aborts if it was not.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);
  final String root;

  Future<String> _dir(String name) async {
    final d = Directory('$root/$name');
    await d.create(recursive: true);
    return d.path;
  }

  @override
  Future<String?> getTemporaryPath() => _dir('tmp');
  @override
  Future<String?> getApplicationSupportPath() => _dir('support');
  @override
  Future<String?> getLibraryPath() => _dir('library');
  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');
  @override
  Future<String?> getApplicationCachePath() => _dir('cache');
  @override
  Future<String?> getDownloadsPath() => _dir('downloads');
}

/// Stand-in for the native open-file dialog: returns [DocsFilePicker.next].
class DocsFilePicker extends FilePicker with MockPlatformInterfaceMixin {
  static List<String> next = [];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (next.isEmpty) return null;
    final files = [
      for (final p in next)
        PlatformFile(
            path: p, name: p.split('/').last, size: File(p).lengthSync()),
    ];
    next = [];
    return FilePickerResult(files);
  }
}

/// Save dialogs (audit export...) land in <HOME>/Downloads; open dialogs cancel.
class DocsFileSelector extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final l = await openFiles();
    return l.isEmpty ? null : l.first;
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    final out = [for (final p in DocsFilePicker.next) XFile(p)];
    DocsFilePicker.next = [];
    return out;
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (DocsFilePicker.next.isEmpty) return null;
    final p = DocsFilePicker.next.first;
    DocsFilePicker.next = [];
    return p;
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async =>
      FileSaveLocation(
          '${Platform.environment['HOME']}/Downloads/${options.suggestedName ?? 'export'}');
}

/// Fake biometric auth: authenticate() stays pending until [complete] is called,
/// so the mobile lock screen can be shown without a real Touch ID prompt.
class DocsLocalAuth extends LocalAuthPlatform with MockPlatformInterfaceMixin {
  static Completer<bool>? _pending;
  static bool _autoApprove = false;

  /// Completes the pending prompt and approves every later one.
  static void complete(bool v) {
    _autoApprove = v;
    _pending?.complete(v);
    _pending = null;
  }

  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<bool> deviceSupportsBiometrics() async => true;
  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => [BiometricType.fingerprint];
  @override
  Future<bool> stopAuthentication() async => true;
  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) {
    if (_autoApprove) return Future.value(true);
    _pending ??= Completer<bool>();
    return _pending!.future;
  }
}

/// Layout of a run: `<root>/home` is the demo HOME, `<root>/pp/*` the
/// path_provider dirs.
class DocsSandbox {
  DocsSandbox(this.root);
  final String root;
  String get home => '$root/home';
}

/// Aborts unless the process runs with a demo HOME (never the owner's).
void assertIsolatedHome() {
  final home = Platform.environment['HOME'] ?? '';
  if (!home.contains('yourssh-docs-home')) {
    throw StateError(
        'refusing to run: HOME=$home is not a yourssh-docs-home demo home. '
        'Launch through tool/docs_journey.sh.');
  }
}

/// Installs every fake. Call BEFORE `app.main`.
DocsSandbox installIsolation({Map<String, Object> prefs = const {}}) {
  assertIsolatedHome();
  final home = Platform.environment['HOME']!;
  final root = Directory(home).parent.path;
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  PathProviderPlatform.instance = _TempPathProvider('$root/pp');
  FilePicker.platform = DocsFilePicker();
  FileSelectorPlatform.instance = DocsFileSelector();
  LocalAuthPlatform.instance = DocsLocalAuth();
  return DocsSandbox(root);
}
