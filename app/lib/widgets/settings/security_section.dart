import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import 'settings_tiles.dart';

/// Settings → Security. Names the store host passwords and key passphrases
/// actually live in, and — the point of the section — makes a downgrade to
/// cleartext prefs visible instead of leaving it in the debug log (issue #91).
class SecuritySettingsSection extends StatefulWidget {
  const SecuritySettingsSection({super.key});

  @override
  State<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState extends State<SecuritySettingsSection> {
  bool _retrying = false;

  static String get _storeName {
    if (Platform.isMacOS) return 'macOS Keychain';
    if (Platform.isWindows) return 'Windows Credential Manager';
    return 'system keyring';
  }

  Future<void> _retry(StorageService storage) async {
    setState(() => _retrying = true);
    final moved = await storage.migratePlaintextSecrets();
    if (!mounted) return;
    setState(() => _retrying = false);
    final left = storage.plaintextSecretKeys.length;
    final msg = left == 0
        ? 'Moved $moved credential(s) into the $_storeName.'
        : '$left credential(s) still could not be stored securely.';
    if (left == 0) {
      AppSnack.success(context, msg);
    } else {
      AppSnack.error(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    return ListenableBuilder(
      listenable: storage.secretStorageRevision,
      builder: (context, _) {
        final plaintext = storage.plaintextSecretKeys.length;
        final secure = plaintext == 0;
        final color = secure ? AppColors.success : AppColors.red;
        return SettingsSection(
          title: 'Security',
          tiles: [
            settingsRowTile(
              key: const ValueKey('settings-credential-storage'),
              label: 'Credential storage',
              description:
                  'Host passwords, sudo passwords and key passphrases are '
                  'kept in the $_storeName',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    secure ? FLucideIcons.lock : FLucideIcons.lockOpen,
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    secure ? 'Encrypted' : 'Plain text',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
            if (!secure)
              settingsRowTile(
                label: '$plaintext credential(s) stored without encryption',
                description:
                    'The system keychain refused these, so they were '
                    'written to the app preferences file as readable text — '
                    'anything that can read your user account can read them.',
                trailing: FButton(
                  key: const ValueKey('settings-secrets-retry'),
                  variant: .outline,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  prefix: _retrying
                      ? const FCircularProgress(size: .sm)
                      : const Icon(FLucideIcons.lockKeyhole),
                  onPress: _retrying ? null : () => _retry(storage),
                  child: const Text('Retry'),
                ),
              ),
          ],
        );
      },
    );
  }
}
