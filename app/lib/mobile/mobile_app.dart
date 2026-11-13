import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/runtime_platform.dart';
import 'lifecycle/background_tasks.dart';
import 'lifecycle/mobile_lifecycle_coordinator.dart';
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
  MobileLifecycleCoordinator? _lifecycle;
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // iOS only: the OS suspends the app and kills its sockets shortly after it
    // leaves the foreground. Android keeps today's behavior (no coordinator).
    if (isIOSPlatform) {
      final c = _lifecycle = MobileLifecycleCoordinator(
        sessions: _bootstrap.sessions,
        forwards: _bootstrap.portForwardService,
        forwardRules: _bootstrap.portForwardProvider,
        tasks: MethodChannelBackgroundTasks(),
      );
      // `inactive` (Face ID sheet, Control Center) is deliberately not handled.
      _lifecycleListener = AppLifecycleListener(
        onPause: c.onBackground,
        onResume: c.onForeground,
      );
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _lifecycle?.dispose();
    _bootstrap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _bootstrap.providers,
      child: MaterialApp(
        navigatorKey: _bootstrap.navigatorKey,
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: buildMobileTheme(),
        builder: ysRootBuilderTouch,
        navigatorObservers: [mobileRouteObserver],
        home: const AppLockGate(child: MobileHomeShell()),
      ),
    );
  }
}
