import 'dart:io';
import 'package:flutter/services.dart';

class BundledPluginInstaller {
  static const _bundledPlugins = {
    'snippets': [
      'plugin.json',
      'index.js',
      'panel/index.html',
    ],
  };

  /// Copies bundled plugin assets to `~/.yourssh/plugins/<name>/` if not already present.
  /// Never overwrites an existing installation.
  static Future<void> ensureInstalled(String pluginName) async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    final target = Directory('$home/.yourssh/plugins/$pluginName');
    if (target.existsSync()) return;

    target.createSync(recursive: true);
    final files = _bundledPlugins[pluginName] ?? [];
    for (final relativePath in files) {
      final assetPath = 'assets/bundled_plugins/$pluginName/$relativePath';
      final data = await rootBundle.load(assetPath);
      final outFile = File('${target.path}/$relativePath')
        ..parent.createSync(recursive: true);
      await outFile.writeAsBytes(data.buffer.asUint8List());
    }
  }
}
