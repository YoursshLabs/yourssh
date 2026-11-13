part of 'hosts_dashboard.dart';

// ── Move to Group Dialog ──────────────────────────────────

class _MoveToGroupDialog extends StatelessWidget {
  final Host host;
  final List<String> groups;
  final void Function(String) onSelect;

  const _MoveToGroupDialog({
    required this.host,
    required this.groups,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final options = ['', ...groups]; // '' = No group
    return YsDialog(
      title: 'Move to group',
      body: SizedBox(
        width: 280,
        child: FItemGroup(
          maxHeight: 320,
          children: [
            for (final g in options)
              FItem(
                title: Text(g.isEmpty ? 'No group' : g),
                selected: g == host.group,
                suffix: g == host.group
                    ? const Icon(FLucideIcons.check,
                        color: YsColors.mutedForeground)
                    : null,
                onPress: () {
                  Navigator.of(context).pop();
                  onSelect(g);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Export Dialog ─────────────────────────────────────────

class _ExportDialog extends StatefulWidget {
  final Host host;
  const _ExportDialog({required this.host});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _showSshConfig = true;

  String get _sshConfigText {
    final alias = widget.host.label.replaceAll(RegExp(r'\s+'), '-');
    return 'Host $alias\n'
        '    HostName ${widget.host.host}\n'
        '    User ${widget.host.username}\n'
        '    Port ${widget.host.port}';
  }

  String get _jsonText {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'label': widget.host.label,
      'host': widget.host.host,
      'port': widget.host.port,
      'username': widget.host.username,
      'authType': widget.host.authType.name,
      'group': widget.host.group,
      'tags': widget.host.tags,
    });
  }

  String get _currentText => _showSshConfig ? _sshConfigText : _jsonText;

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: 'Export host',
      body: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _formatTab(
                  '.ssh/config',
                  selected: _showSshConfig,
                  onTap: () => setState(() => _showSshConfig = true),
                ),
                const SizedBox(width: YsSpace.s2),
                _formatTab(
                  'JSON',
                  selected: !_showSshConfig,
                  onTap: () => setState(() => _showSshConfig = false),
                ),
              ],
            ),
            const SizedBox(height: YsSpace.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(YsSpace.s3),
              decoration: BoxDecoration(
                color: YsColors.background,
                borderRadius: BorderRadius.circular(YsRadius.control),
                border: Border.all(color: YsColors.border),
              ),
              child: SelectableText(
                _currentText,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 12,
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FButton(
          variant: FButtonVariant.primary,
          onPress: () async {
            await Clipboard.setData(ClipboardData(text: _currentText));
            if (!context.mounted) return;
            showYsToast(
              context,
              'Copied to clipboard',
              duration: const Duration(seconds: 2),
            );
          },
          child: const Text('Copy'),
        ),
      ],
    );
  }

  Widget _formatTab(String label,
          {required bool selected, required VoidCallback onTap}) =>
      FButton(
        variant: selected ? .secondary : .ghost,
        size: .sm,
        mainAxisSize: MainAxisSize.min,
        selected: selected,
        onPress: onTap,
        child: Text(label),
      );
}
