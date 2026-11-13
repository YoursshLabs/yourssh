part of 'hosts_dashboard.dart';

// ── Empty State ───────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YsSpace.s6),
      child: YsEmptyState(
        icon: FLucideIcons.server,
        title: 'No hosts yet',
        message: 'Add your first SSH host to get started',
        action: FButton(
          mainAxisSize: MainAxisSize.min,
          onPress: onAdd,
          prefix: const Icon(FLucideIcons.plus),
          child: const Text('New host'),
        ),
      ),
    );
  }
}
