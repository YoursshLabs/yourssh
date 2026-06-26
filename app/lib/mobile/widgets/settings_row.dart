import 'package:flutter/material.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// A single settings / info row supporting:
/// - optional leading icon widget
/// - required title
/// - optional value (rendered in mono/grey)
/// - optional trailing widget (overrides default chevron/toggle)
/// - chevron when [onTap] is set (and no toggle)
/// - amber [Switch] when [toggle] is set
class SettingsRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? toggle;
  final ValueChanged<bool>? onToggle;

  const SettingsRow({
    super.key,
    this.leading,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
    this.toggle,
    this.onToggle,
  });

  Widget _buildTrailing() {
    if (trailing != null) return trailing!;

    if (toggle != null) {
      return Switch(
        value: toggle!,
        onChanged: onToggle,
        activeThumbColor: MobileColors.accent,
        activeTrackColor: MobileColors.accent.withAlpha(77),
      );
    }

    if (onTap != null) {
      return const Icon(
        Icons.chevron_right,
        color: MobileColors.textFaint,
        size: 20,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space3,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: MobileTokens.space3),
          ],
          Expanded(
            child: Text(
              title,
              style: mobileBody(color: MobileColors.textPrimary),
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: MobileTokens.space2),
            Text(
              value!,
              style: mobileMono(size: 13, color: MobileColors.textMuted),
            ),
          ],
          const SizedBox(width: MobileTokens.space2),
          _buildTrailing(),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, child: content);
    }
    return content;
  }
}
