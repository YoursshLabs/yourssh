import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'ys_form_controls.dart';

/// Dismissible banner shown at the top of the app when a newer release is
/// available. [onShowDetails] navigates to the Settings update section.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.onShowDetails});

  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    if (!provider.showBanner) return const SizedBox.shrink();
    final version = provider.latestRelease?.version ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.s4,
        vertical: YsSpace.s2,
      ),
      decoration: BoxDecoration(
        color: YsColors.primary.withValues(alpha: 0.12),
        border: const Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          const Icon(
            FLucideIcons.download,
            size: 16,
            color: YsColors.accentText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New version v$version available',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: YsColors.foreground, fontSize: 13),
            ),
          ),
          FButton(
            variant: .ghost,
            size: .xs,
            mainAxisSize: MainAxisSize.min,
            onPress: onShowDetails,
            child: const Text('Details'),
          ),
          const SizedBox(width: YsSpace.s1),
          FButton(
            variant: .primary,
            size: .xs,
            mainAxisSize: MainAxisSize.min,
            onPress: () => context.read<UpdateProvider>().downloadAndInstall(),
            child: const Text('Update'),
          ),
          const SizedBox(width: YsSpace.s1),
          SettingsIconButton(
            icon: FLucideIcons.x,
            tooltip: 'Dismiss',
            onPress: () => context.read<UpdateProvider>().dismiss(),
          ),
        ],
      ),
    );
  }
}
