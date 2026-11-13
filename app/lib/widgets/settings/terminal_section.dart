import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_util;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/shell_profile.dart';
import '../../providers/settings_provider.dart';
import 'settings_tiles.dart';

/// Settings → Terminal: TERM type, the default local shell and the custom
/// shells the user added.
class TerminalSettingsSection extends StatelessWidget {
  const TerminalSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    SettingsProvider write() => context.read<SettingsProvider>();

    const platformDefault = kPlatformDefaultShellId;
    final profiles = settings.allShellProfiles;
    final ids = {for (final s in profiles) s.id};
    final shellValue =
        settings.defaultShellId != null && ids.contains(settings.defaultShellId)
        ? settings.defaultShellId!
        : platformDefault;

    return SettingsSection(
      title: 'Terminal',
      tiles: [
        settingsRowTile(
          label: 'Terminal emulation type',
          description:
              'TERM reported to the server — applies to new SSH connections',
          trailing: SettingsSelect<String>(
            key: const ValueKey('settings-term-type'),
            value: settings.terminalType,
            options: [for (final t in kTermTypes) (t, t)],
            onChanged: (v) => write().save(terminalType: v),
          ),
        ),
        settingsRowTile(
          label: 'Default local shell',
          description: 'Shell used by new local terminals',
          trailing: SettingsSelect<String>(
            key: const ValueKey('settings-default-shell'),
            value: shellValue,
            options: [
              (platformDefault, 'Platform default'),
              for (final s in profiles) (s.id, s.name),
            ],
            onChanged: (id) =>
                write().setDefaultShellId(id == platformDefault ? null : id),
          ),
        ),
        for (final shell in settings.customShellProfiles)
          settingsRowTile(
            label: shell.name,
            description: [shell.executable, ...shell.args].join(' '),
            trailing: SettingsIconButton(
              key: ValueKey('settings-remove-shell-${shell.id}'),
              icon: FLucideIcons.trash2,
              tooltip: 'Remove custom shell',
              onPress: () => write().removeCustomShellProfile(shell.id),
            ),
          ),
        FTile(
          key: const ValueKey('settings-add-custom-shell'),
          prefix: const Icon(FLucideIcons.plus),
          title: const Text('Add custom shell…'),
          onPress: () => _showAddCustomShellDialog(context),
        ),
      ],
    );
  }
}

Future<void> _showAddCustomShellDialog(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  final profile = await showYsDialog<ShellProfile>(
    context,
    builder: (_) => const _AddShellDialog(),
  );
  if (profile != null) await settings.addCustomShellProfile(profile);
}

/// Stateful so the TextEditingControllers are disposed by the route teardown
/// (State.dispose), not while the dialog's exit animation still references
/// the text fields.
class _AddShellDialog extends StatefulWidget {
  const _AddShellDialog();

  @override
  State<_AddShellDialog> createState() => _AddShellDialogState();
}

class _AddShellDialogState extends State<_AddShellDialog> {
  final _nameCtrl = TextEditingController();
  final _exeCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _exeCtrl.dispose();
    _argsCtrl.dispose();
    super.dispose();
  }

  /// Null when the executable is empty — Add then behaves like Cancel.
  ShellProfile? _buildProfile() {
    final exe = _exeCtrl.text.trim();
    if (exe.isEmpty) return null;
    final name = _nameCtrl.text.trim();
    final argsText = _argsCtrl.text.trim();
    return ShellProfile(
      id: 'custom-${const Uuid().v4()}',
      name: name.isEmpty ? path_util.basename(exe) : name,
      executable: exe,
      args: argsText.isEmpty ? const [] : argsText.split(RegExp(r'\s+')),
      isCustom: true,
    );
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path != null) _exeCtrl.text = path;
  }

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: 'Add custom shell',
      body: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextField(
              key: const ValueKey('custom-shell-name'),
              control: .managed(controller: _nameCtrl),
              label: const Text('Display name'),
            ),
            const SizedBox(height: YsSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FTextField(
                    key: const ValueKey('custom-shell-exe'),
                    control: .managed(controller: _exeCtrl),
                    label: const Text('Executable path'),
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                const SizedBox(width: YsSpace.s1),
                Padding(
                  padding: const EdgeInsets.only(bottom: YsSpace.s1),
                  child: SettingsIconButton(
                    icon: FLucideIcons.folderOpen,
                    tooltip: 'Browse…',
                    onPress: _browse,
                  ),
                ),
              ],
            ),
            const SizedBox(height: YsSpace.s3),
            FTextField(
              key: const ValueKey('custom-shell-args'),
              control: .managed(controller: _argsCtrl),
              label: const Text('Arguments'),
              description: const Text('Space-separated; quoting not supported'),
              autocorrect: false,
              enableSuggestions: false,
            ),
          ],
        ),
      ),
      actions: [
        FButton(
          variant: .outline,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          onPress: () => Navigator.pop(context, _buildProfile()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
