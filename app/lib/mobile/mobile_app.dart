import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import 'mobile_bootstrap.dart';
import 'screens/mobile_home_shell.dart';

/// Root widget for the Android build. Dark-only; reuses the shared
/// [buildAppTheme] so the mobile surface matches desktop. Holds the
/// [MobileBootstrap] and exposes its providers to the tree.
class YourSSHMobileApp extends StatefulWidget {
  const YourSSHMobileApp({super.key});

  @override
  State<YourSSHMobileApp> createState() => _YourSSHMobileAppState();
}

class _YourSSHMobileAppState extends State<YourSSHMobileApp> {
  final _bootstrap = MobileBootstrap();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _bootstrap.providers,
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: buildAppTheme(),
        home: const MobileHomeShell(),
      ),
    );
  }
}
