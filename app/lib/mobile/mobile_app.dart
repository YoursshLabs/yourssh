import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'mobile_bootstrap.dart';
import 'screens/mobile_home_shell.dart';
import 'security/app_lock_gate.dart';
import 'theme/mobile_theme.dart';

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
        home: const AppLockGate(child: MobileHomeShell()),
      ),
    );
  }
}
