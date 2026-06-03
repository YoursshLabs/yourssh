import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/services/update_service.dart';

/// Drives the in-app update flow: debounced launch check + manual check,
/// download, and install hand-off. Surfaces state to the banner and Settings.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider(
    this._service, {
    required this.currentVersion,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _lastCheckKey = 'last_update_check';
  static const _dismissedKey = 'update_dismissed_version';
  static const _minInterval = Duration(hours: 24);

  final UpdateService _service;
  final String currentVersion;
  final DateTime Function() _now;

  UpdateStatus status = UpdateStatus.idle;
  AppRelease? latestRelease;
  double downloadProgress = 0;
  String? errorMessage;
  String? _dismissedVersion;
  File? _downloadedFile;

  bool get showBanner =>
      status == UpdateStatus.available &&
      latestRelease != null &&
      latestRelease!.version != _dismissedVersion;

  /// Checks GitHub for a newer stable release. Auto checks (`manual == false`)
  /// are skipped if the last check was under 24h ago; manual checks always run.
  Future<void> checkForUpdates({bool manual = false}) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedVersion ??= prefs.getString(_dismissedKey);

    if (!manual) {
      final last = prefs.getInt(_lastCheckKey);
      if (last != null) {
        final elapsed = _now().difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        );
        if (elapsed < _minInterval) return;
      }
    }

    status = UpdateStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      final release = await _service.fetchLatestRelease();
      await prefs.setInt(_lastCheckKey, _now().millisecondsSinceEpoch);
      latestRelease = release;
      status = _service.isNewerVersion(currentVersion, release.version)
          ? UpdateStatus.available
          : UpdateStatus.upToDate;
    } on UpdateException catch (e) {
      status = UpdateStatus.error;
      errorMessage = e.message;
    } catch (e) {
      status = UpdateStatus.error;
      errorMessage = 'Could not check for updates: $e';
    }
    notifyListeners();
  }

  /// Downloads the matching artifact and hands it to the OS installer.
  /// Falls back to opening the Releases page when no asset matches the
  /// current OS/arch or when launching the installer fails.
  Future<void> downloadAndInstall() async {
    final release = latestRelease;
    if (release == null) return;

    final asset = _service.assetForPlatform(
      release,
      os: _service.currentOs(),
      arch: _service.currentArch(),
    );
    if (asset == null) {
      await _openReleasePage(release);
      return;
    }

    status = UpdateStatus.downloading;
    downloadProgress = 0;
    errorMessage = null;
    notifyListeners();

    try {
      final file = await _service.downloadAsset(asset, onProgress: (p) {
        downloadProgress = p;
        notifyListeners();
      });
      _downloadedFile = file;
      status = UpdateStatus.readyToInstall;
      notifyListeners();
      await _service.launchInstaller(file);
    } on UpdateException catch (e) {
      status = UpdateStatus.error;
      errorMessage = e.message;
      notifyListeners();
      await _openReleasePage(release);
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    final uri = Uri.tryParse(release.htmlUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Hides the banner for the current latest version (persisted).
  void dismiss() {
    final v = latestRelease?.version;
    if (v == null) return;
    _dismissedVersion = v;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_dismissedKey, v));
    notifyListeners();
  }
}
