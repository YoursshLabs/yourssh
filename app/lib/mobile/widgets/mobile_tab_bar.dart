import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// The four top-level destinations in the mobile app.
enum MobileTab { hosts, snippets, keys, settings }

extension _MobileTabMeta on MobileTab {
  String get label {
    switch (this) {
      case MobileTab.hosts:
        return 'Hosts';
      case MobileTab.snippets:
        return 'Snippets';
      case MobileTab.keys:
        return 'Keys';
      case MobileTab.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case MobileTab.hosts:
        return Icons.dns_outlined;
      case MobileTab.snippets:
        return Icons.code_outlined;
      case MobileTab.keys:
        return Icons.key_outlined;
      case MobileTab.settings:
        return Icons.settings_outlined;
    }
  }
}

/// Blurred 78-px tab bar with 4 destinations.
/// Active tab uses [MobileColors.accent]; inactive uses a muted grey.
class MobileTabBar extends StatelessWidget {
  const MobileTabBar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final MobileTab current;
  final ValueChanged<MobileTab> onSelect;

  static const _inactiveColor = Color(0xFF6D6D72);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MobileTokens.tabBarHeight + bottomPadding,
          color: MobileColors.surface.withValues(alpha: 0.85),
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Row(
            children: MobileTab.values.map((tab) {
              final active = tab == current;
              final color = active ? MobileColors.accent : _inactiveColor;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(tab),
                  child: SizedBox(
                    height: MobileTokens.tabBarHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tab.icon, color: color, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
