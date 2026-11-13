import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../theme/mobile_theme.dart';
import '../theme/toast_inset.dart';

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
        return FLucideIcons.server;
      case MobileTab.snippets:
        return FLucideIcons.code;
      case MobileTab.keys:
        return FLucideIcons.keyRound;
      case MobileTab.settings:
        return FLucideIcons.settings;
    }
  }
}

/// Blurred tab bar with 4 destinations, on [FBottomNavigationBar].
/// Active tab uses the theme primary (amber); inactive uses the muted color.
///
/// While mounted and not covered by an opaque full-screen route it publishes
/// its height through [mobileToastInset] so the root toaster lifts toasts
/// above it (dialogs, sheets and popups keep the inset: the bar is still
/// visible under them). See [MobileRouteObserver].
class MobileTabBar extends StatefulWidget {
  const MobileTabBar({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final MobileTab current;
  final ValueChanged<MobileTab> onSelect;

  @override
  State<MobileTabBar> createState() => _MobileTabBarState();
}

class _MobileTabBarState extends State<MobileTabBar> {
  bool _published = false;

  @override
  void initState() {
    super.initState();
    mobileRouteObserver.revision.addListener(_recompute);
  }

  void _recompute() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    _publish(route == null || !mobileRouteObserver.isCovered(route));
  }

  void _publish(bool visible) {
    if (visible == _published) return;
    _published = visible;
    // Notify after the frame: the toaster rebuilds from this notifier and
    // must not be marked dirty while the tree is building/unmounting.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_published == visible) {
        mobileToastInset.value = visible ? kMobileToastInsetWhenVisible : 0;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recompute();
  }

  @override
  void dispose() {
    mobileRouteObserver.revision.removeListener(_recompute);
    if (_published) {
      _published = false;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_published) mobileToastInset.value = 0;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FBottomNavigationBar(
      index: MobileTab.values.indexOf(widget.current),
      onChange: (i) => widget.onSelect(MobileTab.values[i]),
      safeAreaBottom: true,
      style: FBottomNavigationBarStyleDelta.delta(
        decoration: DecorationDelta.value(
          BoxDecoration(color: MobileColors.surface.withValues(alpha: 0.85)),
        ),
        backgroundFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        // 51 px items + 13.5 px above/below = MobileTokens.tabBarHeight.
        padding: const EdgeInsetsGeometryDelta.value(
          EdgeInsets.symmetric(vertical: 13.5),
        ),
      ),
      children: [
        for (final tab in MobileTab.values)
          FBottomNavigationBarItem(
            key: ValueKey('mobile-tab-${tab.name}'),
            icon: Icon(tab.icon),
            label: Text(tab.label),
            semanticsLabel: tab.label,
          ),
      ],
    );
  }
}
