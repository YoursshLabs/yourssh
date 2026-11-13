part of 'host_detail_panel.dart';

/// OS tile, panel title (New / Edit Host), protocol badge and Close.
class _PanelHeader extends StatelessWidget {
  final _HostDetailPanelState form;
  const _PanelHeader({required this.form});

  @override
  Widget build(BuildContext context) {
    final existing = form.widget.existing;
    final asset = osIconAsset(existing?.detectedOs);
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: YsSpace.s4, right: YsSpace.s3),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          YsOsTile(
            size: 28,
            color: existing == null
                ? YsColors.secondary
                : AppColors.hostColor(existing.id),
            glyph: asset == null
                ? Icon(
                    existing == null ? FLucideIcons.plus : FLucideIcons.server,
                  )
                : SvgPicture.asset(
                    asset,
                    width: 15,
                    height: 15,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
          ),
          const SizedBox(width: YsSpace.s3),
          Flexible(
            child: Text(
              form._isNew ? 'New Host' : 'Edit Host',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YsColors.foreground,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (form._isGraphical) ...[
            const SizedBox(width: YsSpace.s2),
            ProtocolBadge(form._protocol),
          ],
          const Spacer(),
          Tooltip(
            message: 'Close',
            excludeFromSemantics: true,
            child: FButton.icon(
              variant: .ghost,
              size: .sm,
              semanticsLabel: 'Close',
              onPress: form.widget.onClose,
              child: const Icon(FLucideIcons.x),
            ),
          ),
        ],
      ),
    );
  }
}
