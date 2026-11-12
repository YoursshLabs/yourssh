import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/app_release.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/update_provider.dart';

/// Top-level sections reachable from the sidebar.
enum NavSection {
  hosts,
  keychain,
  portForwarding,
  sftp,
  knownHosts,
  recordings,
  audit,
  settings,
  plugins,
}

/// The app's left navigation, built on forui's [FSidebar].
///
/// Layout, top to bottom: brand header; groups Connections, Files & Transfer,
/// Tools (Local Terminal action, Recordings, Audit Log, then enabled Dart
/// plugins and JS script panels) and Security; footer with Plugins, Settings
/// and the version / update line. Width is [kYsSidebarWidth] (set in the
/// forui theme), so the main content area is not resized.
class AppSidebar extends StatelessWidget {
  final NavSection selected;
  final String? activePluginId;
  final String? activeScriptPanel;
  final ValueChanged<NavSection> onSelect;
  final ValueChanged<String> onSelectPlugin;
  final ValueChanged<String> onSelectScriptPanel;
  final VoidCallback onOpenLocalTerminal;

  const AppSidebar({
    super.key,
    required this.selected,
    required this.activePluginId,
    required this.activeScriptPanel,
    required this.onSelect,
    required this.onSelectPlugin,
    required this.onSelectScriptPanel,
    required this.onOpenLocalTerminal,
  });

  @override
  Widget build(BuildContext context) {
    final plugins = context.watch<PluginProvider>().enabledPlugins;
    final panels = context.watch<PluginUiRegistry>().panels;

    return FSidebar(
      header: const _BrandHeader(),
      footer: Column(
        children: [
          FSidebarGroup(
            children: [
              _navItem(FLucideIcons.puzzle, 'Plugins', NavSection.plugins),
              _navItem(FLucideIcons.settings, 'Settings', NavSection.settings),
            ],
          ),
          const _VersionLine(),
        ],
      ),
      children: [
        FSidebarGroup(
          label: const Text('Connections'),
          children: [
            _navItem(FLucideIcons.server, 'Hosts', NavSection.hosts),
            _navItem(
              FLucideIcons.arrowLeftRight,
              'Port Forwarding',
              NavSection.portForwarding,
            ),
            _navItem(
              FLucideIcons.shieldCheck,
              'Known Hosts',
              NavSection.knownHosts,
            ),
          ],
        ),
        FSidebarGroup(
          label: const Text('Files & Transfer'),
          children: [_navItem(FLucideIcons.folderOpen, 'SFTP', NavSection.sftp)],
        ),
        FSidebarGroup(
          label: const Text('Tools'),
          children: [
            // Action, not a nav target: local terminal lives in the top tab bar.
            FSidebarItem(
              key: const ValueKey('sidebar-local-terminal'),
              icon: const Icon(FLucideIcons.laptop),
              label: const Text('Local Terminal'),
              onPress: onOpenLocalTerminal,
            ),
            _navItem(FLucideIcons.video, 'Recordings', NavSection.recordings),
            _navItem(FLucideIcons.scrollText, 'Audit Log', NavSection.audit),
            for (final plugin in plugins) _pluginItem(plugin),
            for (final panel in panels)
              FSidebarItem(
                key: ValueKey('sidebar-script-${panel.pluginId}'),
                icon: const Icon(FLucideIcons.code),
                label: Text(panel.title),
                selected: activeScriptPanel == panel.pluginId,
                onPress: () => onSelectScriptPanel(panel.pluginId),
              ),
          ],
        ),
        FSidebarGroup(
          label: const Text('Security'),
          children: [
            _navItem(FLucideIcons.keyRound, 'Keychain', NavSection.keychain),
          ],
        ),
      ],
    );
  }

  Widget _navItem(IconData icon, String label, NavSection section) {
    return FSidebarItem(
      key: ValueKey('sidebar-nav-${section.name}'),
      icon: Icon(icon),
      label: Text(label),
      selected:
          activePluginId == null &&
          activeScriptPanel == null &&
          selected == section,
      onPress: () => onSelect(section),
    );
  }

  Widget _pluginItem(YourSSHPlugin plugin) {
    return FSidebarItem(
      key: ValueKey('sidebar-plugin-${plugin.id}'),
      icon: Icon(plugin.icon),
      label: Text(plugin.name),
      selected: activePluginId == plugin.id,
      onPress: () => onSelectPlugin(plugin.id),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        YsSpace.s4,
        YsSpace.s4,
        YsSpace.s4,
        YsSpace.s2,
      ),
      child: Row(
        spacing: YsSpace.s2,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(YsRadius.control),
            child: Image.asset(
              'assets/app_icon.png',
              width: 24,
              height: 24,
              errorBuilder: (_, _, _) => Icon(
                FLucideIcons.terminal,
                size: 18,
                color: theme.colors.mutedForeground,
              ),
            ),
          ),
          Flexible(
            child: Text(
              'YourSSH',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateProvider>();
    final state = switch (update.status) {
      UpdateStatus.checking => 'checking for updates',
      UpdateStatus.upToDate => 'up to date',
      UpdateStatus.available => 'update available',
      UpdateStatus.downloading => 'downloading update',
      UpdateStatus.readyToInstall => 'ready to install',
      UpdateStatus.idle || UpdateStatus.error => null,
    };
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        YsSpace.s4,
        YsSpace.s2,
        YsSpace.s4,
        YsSpace.s2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'YourSSH v${update.currentVersion}${state == null ? '' : ' · $state'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.body.xs.copyWith(
            color: update.status == UpdateStatus.available
                ? YsColors.primary
                : theme.colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
