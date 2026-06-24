import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'screens/mobile_home_shell.dart';

/// Root widget for the Android build. Dark-only; reuses the shared
/// [buildAppTheme] so the mobile surface matches desktop. Providers/services
/// are wired here starting in M2.
class YourSSHMobileApp extends StatelessWidget {
  const YourSSHMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YourSSH',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildAppTheme(),
      home: const MobileHomeShell(),
    );
  }
}
