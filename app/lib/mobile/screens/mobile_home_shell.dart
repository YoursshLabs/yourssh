import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../security/tofu_watcher.dart';
import 'mobile_add_host_screen.dart';
import 'mobile_hosts_screen.dart';
import 'mobile_sessions_screen.dart';
import 'mobile_settings_screen.dart';
import 'mobile_sftp_screen.dart';

/// Bottom-navigation shell for the Android app. Hosts (0) and Sessions (1) are
/// live; SFTP (2) and Settings (3) are placeholders filled in M4/M5.
class MobileHomeShell extends StatefulWidget {
  const MobileHomeShell({super.key});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  int _index = 0;

  static const _labels = ['Hosts', 'Sessions', 'SFTP', 'Settings'];
  static const _icons = [
    Icons.dns_outlined,
    Icons.terminal_outlined,
    Icons.folder_outlined,
    Icons.settings_outlined,
  ];

  void _openAddHost() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MobileAddHostScreen()),
    );
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return MobileHostsScreen(
          onConnected: () => setState(() => _index = 1),
          onAddHost: _openAddHost,
        );
      case 1:
        return const MobileSessionsScreen();
      case 2:
        return const MobileSftpScreen();
      case 3:
        return const MobileSettingsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: TofuWatcher(child: _body()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}
