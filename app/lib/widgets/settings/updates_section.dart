import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/app_release.dart';
import '../../providers/update_provider.dart';
import 'settings_tiles.dart';

/// Settings → Updates: current version, status, manual check and
/// download-and-install.
class UpdatesSettingsSection extends StatelessWidget {
  const UpdatesSettingsSection({super.key});

  static String _statusText(UpdateProvider u) {
    switch (u.status) {
      case UpdateStatus.checking:
        return 'Checking…';
      case UpdateStatus.upToDate:
        return 'You are on the latest version';
      case UpdateStatus.available:
        return 'New version v${u.latestRelease?.version ?? '?'} available';
      case UpdateStatus.downloading:
        return 'Downloading…';
      case UpdateStatus.readyToInstall:
        return 'Installer opened — complete it to finish updating';
      case UpdateStatus.error:
        return u.errorMessage ?? 'Could not check for updates';
      case UpdateStatus.idle:
        return 'Click "Check for updates" to look for a new version';
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateProvider>();
    final notes = update.status == UpdateStatus.available
        ? update.latestRelease?.notes ?? ''
        : '';
    return SettingsSection(
      title: 'Updates',
      tiles: [
        settingsRowTile(
          label: 'Current version',
          trailing: Text(
            'v${update.currentVersion}',
            style: const TextStyle(
              color: YsColors.mutedForeground,
              fontSize: 13,
            ),
          ),
        ),
        settingsRowTile(
          label: 'Status',
          description: _statusText(update),
          trailing: update.status == UpdateStatus.downloading
              ? SizedBox(
                  width: 120,
                  child: FDeterminateProgress(
                    value: update.downloadProgress.clamp(0.0, 1.0),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: YsSpace.s2,
                  children: [
                    if (update.status == UpdateStatus.available)
                      FButton(
                        key: const ValueKey('update-install'),
                        size: .sm,
                        mainAxisSize: MainAxisSize.min,
                        prefix: const Icon(FLucideIcons.download),
                        onPress: () =>
                            context.read<UpdateProvider>().downloadAndInstall(),
                        child: const Text('Download & install'),
                      ),
                    FButton(
                      key: const ValueKey('update-check'),
                      variant: .outline,
                      size: .sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: update.status == UpdateStatus.checking
                          ? null
                          : () => context
                                .read<UpdateProvider>()
                                .checkForUpdates(manual: true),
                      child: const Text('Check for updates'),
                    ),
                  ],
                ),
        ),
        if (notes.isNotEmpty)
          settingsContentTile(
            child: Text(
              notes,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
