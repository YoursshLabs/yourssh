import 'package:flutter/widgets.dart';

import 'mobile_tokens.dart';

/// Bottom offset the root toaster applies so toasts clear the mobile tab bar.
/// Non-zero only while the tab bar is visible. Written by `MobileTabBar`,
/// read by `ysRootBuilderTouch`.
final ValueNotifier<double> mobileToastInset = ValueNotifier<double>(0);

/// Height of the bar the toast inset clears.
const double kMobileToastInsetWhenVisible = MobileTokens.tabBarHeight;

/// Tracks each navigator's route stack so the tab bar can tell whether it is
/// hidden. The bar is hidden only when an opaque route (a full-screen
/// `PageRoute`) sits above its own route. Dialogs, bottom sheets and popup
/// menus are non-opaque, so the bar stays visible under them and toasts keep
/// their offset.
///
/// Register [mobileRouteObserver] in `MaterialApp.navigatorObservers`. When it
/// is not registered the bar is assumed visible.
class MobileRouteObserver extends NavigatorObserver {
  final Expando<List<Route<dynamic>>> _stacks = Expando('mobile route stacks');

  /// Bumped on every stack change; the tab bar listens to re-evaluate.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<Route<dynamic>>? _stackOf(Route<dynamic> route) {
    final nav = route.navigator;
    if (nav == null) return null;
    return _stacks[nav] ??= <Route<dynamic>>[];
  }

  void _changed() => revision.value++;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stackOf(route)?.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stackOf(route)?.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stackOf(route)?.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final stack = _stackOf(oldRoute);
      final i = stack?.indexOf(oldRoute) ?? -1;
      if (stack != null && i >= 0) {
        if (newRoute != null) {
          stack[i] = newRoute;
        } else {
          stack.removeAt(i);
        }
      }
    }
    _changed();
  }

  /// True when an opaque route is stacked above [route] in its navigator.
  bool isCovered(Route<dynamic> route) {
    final stack = _stackOf(route);
    if (stack == null) return false;
    final i = stack.indexOf(route);
    if (i < 0) return false;
    return stack.skip(i + 1).any((r) => r is TransitionRoute && r.opaque);
  }
}

final MobileRouteObserver mobileRouteObserver = MobileRouteObserver();
