// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';
import 'ys_theme.dart';

/// Root wrapper for a plugin screen.
///
/// Inside the app (`ysRootBuilder` above the Navigator) the Ys [FTheme] is
/// already in scope, so this passes [child] through untouched. When a plugin
/// screen is mounted somewhere that theme is missing (a host without the root
/// builder, a bare `MaterialApp`), forui would silently fall back to its stock
/// light theme; this puts the Ys forui theme, a toaster and the Material
/// fallback theme above [child] instead.
class YsPluginHost extends StatelessWidget {
  const YsPluginHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // forui returns its stock light theme when no FTheme is in scope.
    if (FTheme.of(context).colors.primary == YsColors.primary) return child;
    return Theme(
      data: ysMaterialTheme(),
      child: FTheme(
        data: ysThemeData(),
        child: FToaster(child: Material(color: YsColors.background, child: child)),
      ),
    );
  }
}
