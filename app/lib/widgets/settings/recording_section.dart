import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../providers/settings_provider.dart';
import 'settings_tiles.dart';

/// Settings → Recording: where `.cast` files go and whether secrets are
/// redacted before they are written.
class RecordingSettingsSection extends StatelessWidget {
  const RecordingSettingsSection({super.key});

  Future<void> _choosePath(BuildContext context) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose recordings folder',
    );
    if (result != null && context.mounted) {
      await context.read<SettingsProvider>().save(recordingPath: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return SettingsSection(
      title: 'Recording',
      tiles: [
        settingsRowTile(
          label: 'Recording path',
          descriptionWidget: Text(
            settings.recordingPath,
            key: const ValueKey('settings-recording-path'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: kYsMonoFontFamily,
              fontFamilyFallback: kYsMonoFontFallback,
              fontSize: 12,
            ),
          ),
          trailing: FButton(
            key: const ValueKey('settings-recording-change'),
            variant: .outline,
            size: .sm,
            mainAxisSize: MainAxisSize.min,
            onPress: () => _choosePath(context),
            child: const Text('Change…'),
          ),
        ),
        settingsSwitchTile(
          key: const ValueKey('settings-recording-redaction'),
          label: 'Redact secrets in recordings',
          description:
              'Mask passwords/tokens (AuditRedactor patterns) before writing '
              '.cast — replay timing becomes per-line; per-host opt-out in the '
              'host panel',
          value: settings.recordingRedactionEnabled,
          onChange: (v) => context.read<SettingsProvider>().save(
            recordingRedactionEnabled: v,
          ),
        ),
      ],
    );
  }
}
