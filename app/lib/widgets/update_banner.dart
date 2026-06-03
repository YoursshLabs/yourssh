import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/theme/app_theme.dart';

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

    return Material(
      color: AppColors.accent.withValues(alpha: 0.12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt, size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'New version v$version available',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onShowDetails,
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              child: const Text('Details'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => context.read<UpdateProvider>().downloadAndInstall(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Update'),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              onPressed: () => context.read<UpdateProvider>().dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
