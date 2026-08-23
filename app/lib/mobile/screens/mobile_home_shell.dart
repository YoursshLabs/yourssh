import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../security/tofu_watcher.dart';
import '../services/host_reachability_probe.dart';
import '../widgets/mobile_tab_bar.dart';
import 'mobile_hosts_screen.dart';
import 'mobile_keys_screen.dart';
import 'mobile_settings_screen.dart';
import 'mobile_snippets_screen.dart';

/// Bottom-navigation shell for the Android app.
/// Four tabs: Hosts · Snippets · Keys · Settings.
/// Tab bodies are temporary placeholders until tasks T8/T9 land.
class MobileHomeShell extends StatefulWidget {
  const MobileHomeShell({super.key});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  MobileTab _current = MobileTab.hosts;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HostReachabilityProbe(),
      child: Scaffold(
        body: TofuWatcher(
          child: IndexedStack(
            index: MobileTab.values.indexOf(_current),
            children: const [
              MobileHostsScreen(),
              MobileSnippetsScreen(),
              MobileKeysScreen(),
              MobileSettingsScreen(),
            ],
          ),
        ),
        bottomNavigationBar: MobileTabBar(
          current: _current,
          onSelect: (tab) => setState(() => _current = tab),
        ),
      ),
    );
  }
}
