import 'package:flutter/material.dart';

import '../widgets/mobile_tab_bar.dart';

/// Bottom-navigation shell for the Android app.
/// Four tabs: Hosts · Snippets · Keys · Settings.
/// Tab bodies are temporary placeholders until tasks T6/T8/T9 land.
class MobileHomeShell extends StatefulWidget {
  const MobileHomeShell({super.key});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  MobileTab _current = MobileTab.hosts;

  static const _bodies = <MobileTab, Widget>{
    MobileTab.hosts: Center(child: Text('Hosts')),
    MobileTab.snippets: Center(child: Text('Snippets')),
    MobileTab.keys: Center(child: Text('Keys')),
    MobileTab.settings: Center(child: Text('Settings')),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: MobileTab.values.indexOf(_current),
        children: MobileTab.values.map((t) => _bodies[t]!).toList(),
      ),
      bottomNavigationBar: MobileTabBar(
        current: _current,
        onSelect: (tab) => setState(() => _current = tab),
      ),
    );
  }
}
