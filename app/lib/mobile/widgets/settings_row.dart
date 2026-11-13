import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'press_tint.dart';

/// A single settings / info row supporting:
/// - optional leading icon widget
/// - required title
/// - optional value (rendered in mono/grey)
/// - optional trailing widget (overrides default chevron/toggle)
/// - chevron when [onTap] is set (and no toggle)
/// - [FSwitch] when [toggle] is set
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
      return FSwitch(value: toggle!, onChange: onToggle);
    }

    if (onTap != null) {
      return const Icon(
        FLucideIcons.chevronRight,
        color: MobileColors.textFaint,
        size: 20,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: MobileTokens.touchTarget),
      child: Padding(
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: MobileTokens.space2),
              Flexible(
                child: Text(
                  value!,
                  style: mobileMono(size: 13, color: MobileColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (trailing != null || toggle != null || onTap != null) ...[
              const SizedBox(width: MobileTokens.space2),
              _buildTrailing(),
            ],
          ],
        ),
      ),
    );

    if (onTap != null) {
      return FTappable.static(
        onPress: onTap,
        builder: (context, variants, child) =>
            mobilePressTint(variants, child!),
        child: content,
      );
    }
    return content;
  }
}
