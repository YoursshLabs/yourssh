import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:yourssh/models/app_release.dart';

/// Thrown when the update flow cannot complete (network, parse, no asset, IO).
class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => 'UpdateException: $message';
}

/// Network + platform glue for the in-app update flow.
class UpdateService {
  UpdateService({
    http.Client? client,
    this.repo = 'YoursshLabs/yourssh',
    Directory? downloadDir,
  })  : _client = client ?? http.Client(),
        // ignore: prefer_initializing_formals
        _downloadDir = downloadDir;

  final http.Client _client;
  final Directory? _downloadDir;
  final String repo;

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

  /// Picks the best matching asset for [os] (`macos`/`windows`/`linux`) and
  /// [arch] (`arm64`/`x64`/`amd64`). Returns null when no artifact matches
  /// (e.g. macOS x64 — only arm64 is shipped); callers then fall back to the
  /// browser. For each platform the candidate names are tried in preference
  /// order and the first asset whose name matches is returned.
  ReleaseAsset? assetForPlatform(
    AppRelease release, {
    required String os,
    required String arch,
  }) {
    List<String> candidates() {
      switch (os) {
        case 'macos':
          return arch == 'arm64' ? const ['macOS-arm64.dmg'] : const [];
        case 'linux':
          return arch == 'arm64'
              ? const ['_arm64.deb', 'Linux-arm64.tar.gz']
              : const ['_amd64.deb', 'Linux-x86_64.tar.gz'];
        default:
          return const [];
      }
    }

    // Windows needs both an installer-vs-portable preference AND an arch match,
    // so handle it explicitly; other platforms match a single fragment.
    if (os == 'windows') {
      final archFrag = arch == 'arm64' ? 'arm64' : 'x64';
      // Preference: Setup (installer) first, then portable.
      for (final wantSetup in const [true, false]) {
        for (final a in release.assets) {
          final isSetup = a.name.contains('Setup.');
          if (a.name.contains(archFrag) &&
              a.name.endsWith('.exe') &&
              isSetup == wantSetup) {
            return a;
          }
        }
      }
      return null;
    }

    for (final frag in candidates()) {
      for (final a in release.assets) {
        if (a.name.contains(frag)) return a;
      }
    }
    return null;
  }

  /// Fetches the latest *stable* release (GitHub's `releases/latest` excludes
  /// drafts and pre-releases). Throws [UpdateException] on network/HTTP/parse
  /// failure.
  Future<AppRelease> fetchLatestRelease() async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    try {
      final res = await _client.get(uri, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      });
      if (res.statusCode != 200) {
        throw UpdateException('GitHub responded ${res.statusCode}');
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        throw UpdateException('Unexpected response shape');
      }
      return AppRelease.fromJson(body);
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException('Could not check for updates: $e');
    }
  }

  /// CPU architecture token used by [assetForPlatform].
  /// macOS only ships arm64; Windows reads PROCESSOR_ARCHITECTURE; Linux
  /// shells out to `uname -m`.
  String currentArch() {
    if (Platform.isMacOS) {
      // Only arm64 artifacts are published. Detect the real arch so Intel Macs
      // return 'x64' -> assetForPlatform returns null -> caller falls back to
      // the browser, rather than being handed an arm64-only DMG.
      try {
        final m = Process.runSync('uname', const ['-m']).stdout.toString().trim();
        return (m == 'arm64' || m == 'aarch64') ? 'arm64' : 'x64';
      } catch (_) {
        return 'arm64';
      }
    }
    if (Platform.isWindows) {
      final p = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
      return p.contains('ARM64') ? 'arm64' : 'x64';
    }
    if (Platform.isLinux) {
      try {
        final m = Process.runSync('uname', const ['-m']).stdout.toString().trim();
        return (m == 'aarch64' || m == 'arm64') ? 'arm64' : 'amd64';
      } catch (_) {
        return 'amd64';
      }
    }
    return 'x64';
  }

  /// OS token used by [assetForPlatform].
  String currentOs() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  /// Streams [asset] to the Downloads directory, reporting progress 0.0..1.0.
  /// Removes a partial file and throws [UpdateException] on failure.
  Future<File> downloadAsset(
    ReleaseAsset asset, {
    required void Function(double) onProgress,
  }) async {
    // Enforce HTTPS: use tryParse so a malformed URL throws UpdateException,
    // not a raw FormatException.
    final rawUrl = asset.downloadUrl;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https') {
      throw UpdateException('Download URL must use HTTPS: $rawUrl');
    }
    final dir = _downloadDir ?? await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final file = File('${dir.path}/${asset.name}');
    final req = http.Request('GET', uri);
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      throw UpdateException('Download failed (${res.statusCode})');
    }
    final total = res.contentLength ?? asset.size;
    var received = 0;
    final sink = file.openWrite();
    final digestOutput = AccumulatorSink<Digest>();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    try {
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        digestInput.add(chunk);
        if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } catch (e) {
      // Close the sink before deleting so the partial file is releasable
      // (notably on Windows, where an open handle blocks deletion).
      await sink.close().catchError((_) {});
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (e is UpdateException) rethrow;
      throw UpdateException('Download failed: $e');
    } finally {
      digestInput.close();
    }
    await sink.close();

    // Verify SHA-256 digest when the GitHub API provided one.
    final assetDigest = asset.digest;
    if (assetDigest != null && assetDigest.isNotEmpty) {
      final expected = assetDigest.startsWith('sha256:')
          ? assetDigest.substring(7)
          : assetDigest;
      final computed = digestOutput.events.single.toString();
      if (computed != expected) {
        try {
          await file.delete();
        } catch (_) {}
        throw UpdateException(
            'Digest mismatch: expected $expected, got $computed');
      }
    }

    onProgress(1.0);
    return file;
  }

  /// Hands [file] off to the OS installer. macOS strips quarantine then opens
  /// the DMG; Windows runs the installer exe; Linux opens with the desktop
  /// handler. Throws [UpdateException] on failure.
  Future<void> launchInstaller(File file) async {
    final path = file.path;
    try {
      if (Platform.isMacOS) {
        // Best-effort: our own download usually carries no quarantine xattr,
        // but strip it anyway so Gatekeeper does not block the new build.
        await Process.run('xattr', ['-dr', 'com.apple.quarantine', path]);
        final r = await Process.run('open', [path]);
        if (r.exitCode != 0) throw UpdateException('open failed: ${r.stderr}');
      } else if (Platform.isWindows) {
        // Detached: we intentionally don't wait for the installer to finish.
        await Process.start(path, const [], mode: ProcessStartMode.detached);
      } else {
        final r = await Process.run('xdg-open', [path]);
        if (r.exitCode != 0) throw UpdateException('xdg-open failed: ${r.stderr}');
      }
    } catch (e) {
      if (e is UpdateException) rethrow;
      throw UpdateException('Could not launch installer: $e');
    }
  }
}
