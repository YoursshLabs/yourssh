import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Bottom-navigation shell for the Android app. M1 renders placeholder bodies;
/// each destination is filled in over later milestones (M2 terminal, M3 sync,
/// M4 SFTP/snippets, M5 settings/app-lock).
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Text(
            '${_labels[_index]} — coming soon',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ),
      ),
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
