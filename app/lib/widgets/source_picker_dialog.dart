import 'package:flutter/material.dart';

import '../models/host.dart';
import '../models/panel_source.dart';

import 'package:yourssh_ui/yourssh_ui.dart';

/// Picker for an SFTP panel slot's source: the local filesystem (pinned
/// first) or any saved host. Pops a [PanelSource], or null when dismissed.
class SourcePickerDialog extends StatelessWidget {
  final List<Host> hosts;
  final PanelSource? current;

  const SourcePickerDialog({super.key, required this.hosts, this.current});

  @override
  Widget build(BuildContext context) {
    return YsDialogFrame(
      maxWidth: 380,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                YsSpace.s4,
                YsSpace.s3,
                YsSpace.s2,
                YsSpace.s2,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: YsColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    FLucideIcons.server,
                    size: 15,
                    color: YsColors.mutedForeground,
                  ),
                  const SizedBox(width: YsSpace.s2),
                  const Expanded(
                    child: Text(
                      'Select Source',
                      style: TextStyle(
                        color: YsColors.foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    excludeFromSemantics: true,
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      size: FButtonSizeVariant.xs,
                      semanticsLabel: 'Close',
                      onPress: () => Navigator.pop(context),
                      child: const Icon(FLucideIcons.x),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(YsSpace.s2),
                children: [
                  _SourceTile(
                    icon: FLucideIcons.laptop,
                    title: 'Local',
                    subtitle: 'This computer',
                    active: current is LocalSource,
                    onTap: () => Navigator.pop(context, const LocalSource()),
                  ),
                  for (final h in hosts)
                    _SourceTile(
                      icon: FLucideIcons.server,
                      title: h.label,
                      subtitle: '${h.username}@${h.host}:${h.port}',
                      active:
                          current is HostSource &&
                          (current as HostSource).host.id == h.id,
                      onTap: () => Navigator.pop(context, HostSource(h)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FTile(
      selected: active,
      onPress: onTap,
      prefix: Icon(icon, size: 16, color: YsColors.primary),
      title: Text(title, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: kYsMonoFontFamily,
          fontFamilyFallback: kYsMonoFontFallback,
          fontSize: 11,
        ),
      ),
      suffix: active
          ? const Icon(FLucideIcons.check, size: 14, color: YsColors.primary)
          : null,
    );
  }
}
