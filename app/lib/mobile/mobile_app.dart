import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'mobile_bootstrap.dart';
import 'screens/mobile_home_shell.dart';
import 'security/app_lock_gate.dart';
import '../theme/app_theme.dart' show ysRootBuilderTouch;
import 'theme/mobile_theme.dart';
import 'theme/toast_inset.dart';

/// Root widget for the Android build. Dark-only; uses [buildMobileTheme]
/// for the mobile-specific design language. Holds the [MobileBootstrap]
/// and exposes its providers to the tree.
class YourSSHMobileApp extends StatefulWidget {
  const YourSSHMobileApp({super.key});

  @override
  State<YourSSHMobileApp> createState() => _YourSSHMobileAppState();
}

class _YourSSHMobileAppState extends State<YourSSHMobileApp> {
  final _bootstrap = MobileBootstrap();

  @override
  void dispose() {
    _bootstrap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _bootstrap.providers,
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: buildMobileTheme(),
        // The lock wraps the whole navigator, so pushed routes and dialogs are
        // covered too. It sits outside ysRootBuilderTouch's FToaster so toasts
        // stay under the lock as well.
        builder: (c, child) => AppLockGate(
          child: ysRootBuilderTouch(c, child),
        ),
        navigatorObservers: [mobileRouteObserver],
        home: const MobileHomeShell(),
      ),
    );
  }
}
