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

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  AppRelease? _latestRelease;
  AppRelease? get latestRelease => _latestRelease;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _dismissedVersion;

  bool get showBanner =>
      _status == UpdateStatus.available &&
      _latestRelease != null &&
      _latestRelease!.version != _dismissedVersion;

  /// Checks GitHub for a newer stable release. Auto checks (`manual == false`)
  /// are skipped if the last check was under 24h ago; manual checks always run.
  Future<void> checkForUpdates({bool manual = false}) async {
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.readyToInstall) {
      return;
    }

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

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final release = await _service.fetchLatestRelease();
      await prefs.setInt(_lastCheckKey, _now().millisecondsSinceEpoch);
      _latestRelease = release;
      _status = _service.isNewerVersion(currentVersion, release.version)
          ? UpdateStatus.available
          : UpdateStatus.upToDate;
    } on UpdateException catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.message;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = 'Could not check for updates: $e';
    }
    notifyListeners();
  }

  /// Downloads the matching artifact and hands it to the OS installer.
  /// Falls back to opening the Releases page when no asset matches the
  /// current OS/arch or when launching the installer fails.
  Future<void> downloadAndInstall() async {
    if (_status == UpdateStatus.downloading) return;

    final release = _latestRelease;
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

    _status = UpdateStatus.downloading;
    _downloadProgress = 0;
    _errorMessage = null;
    notifyListeners();

    try {
      final file = await _service.downloadAsset(asset, onProgress: (p) {
        _downloadProgress = p;
        notifyListeners();
      });
      _status = UpdateStatus.readyToInstall;
      notifyListeners();
      await _service.launchInstaller(file);
    } on UpdateException catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      await _openReleasePage(release);
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = 'Install failed: $e';
      notifyListeners();
      await _openReleasePage(release);
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    if (release.htmlUrl.isEmpty) return;
    final uri = Uri.tryParse(release.htmlUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Hides the banner for the current latest version. The persisted write is
  /// best-effort: the UI updates immediately and, at worst, the dismissal is
  /// forgotten on next launch.
  void dismiss() {
    final v = _latestRelease?.version;
    if (v == null) return;
    _dismissedVersion = v;
    notifyListeners();
    _persistDismissed(v);
  }

  Future<void> _persistDismissed(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissedKey, version);
    } catch (_) {
      // Best-effort; ignore persistence failures.
    }
  }
}
