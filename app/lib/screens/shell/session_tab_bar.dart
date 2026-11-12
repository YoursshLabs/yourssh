import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/ys_menu.dart';

import '../../models/shell_profile.dart';
import '../../models/terminal_session.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/session_tab.dart';
import 'app_sidebar.dart';

/// The top browser-style tab bar: pinned Home/SFTP tabs, drag-reorderable
/// session tabs, the "+" menu and the notification bell. Built on [YsTab].
class SessionTabBar extends StatelessWidget {
  final List<AppSession> sessions;
  final AppSession? active;
  final NavSection nav;
  final bool viewingTerminal;
  final ValueChanged<NavSection> onNavSelect;
  final ValueChanged<String> onSessionTap;
  final VoidCallback onAddSession;
  final void Function({ShellProfile? profile, bool platformDefault})
      onAddLocalSession;
  final VoidCallback onShowUpdateDetails;
  final ValueChanged<String> onOpenSession;

  const SessionTabBar({
    super.key,
    required this.sessions,
    required this.active,
    required this.nav,
    required this.viewingTerminal,
    required this.onNavSelect,
    required this.onSessionTap,
    required this.onAddSession,
    required this.onAddLocalSession,
    required this.onShowUpdateDetails,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SessionProvider>();
    return Container(
      height: YsTab.height,
      decoration: const BoxDecoration(
        color: YsColors.chrome,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          // Pinned nav shortcuts
          YsTab(
            leading: const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(FLucideIcons.house),
            ),
            label: const Text('Home'),
            active: nav == NavSection.hosts && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.hosts),
          ),
          YsTab(
            leading: const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(FLucideIcons.folder),
            ),
            label: const Text('SFTP'),
            active: nav == NavSection.sftp && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.sftp),
          ),
          Container(width: 1, height: 18, color: YsColors.border),
          const SizedBox(width: 4),
          // Session tabs (scrollable, drag-reorderable)
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: sessions.length,
              onReorderItem: provider.reorderSessionItem,
              itemBuilder: (context, index) {
                final s = sessions[index];
                return ReorderableDragStartListener(
                  key: ValueKey(s.id),
                  index: index,
                  child: SessionTab(
                    session: s,
                    isActive: s.id == active?.id && viewingTerminal,
                    provider: provider,
                    onTap: () => onSessionTap(s.id),
                  ),
                );
              },
            ),
          ),
          _AddTabButton(onNewSsh: onAddSession, onNewLocal: onAddLocalSession),
          NotificationBellBtn(
            onShowUpdateDetails: onShowUpdateDetails,
            onOpenSession: onOpenSession,
          ),
        ],
      ),
    );
  }
}

class _AddTabButton extends StatelessWidget {
  final VoidCallback onNewSsh;
  final void Function({ShellProfile? profile, bool platformDefault})
      onNewLocal;
  const _AddTabButton({required this.onNewSsh, required this.onNewLocal});

  Future<void> _showAddMenu(BuildContext context) async {
    // Same set as the Settings dropdown: platform default + detected + custom.
    final profiles = context.read<SettingsProvider>().allShellProfiles;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height));
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
      color: kYsMenuColor,
      shape: kYsMenuShape,
      items: [
        ysMenuItem('ssh', FLucideIcons.server, 'New SSH session'),
        ysMenuItem('local', FLucideIcons.laptop, 'New local terminal'),
        if (profiles.isNotEmpty) const PopupMenuDivider(height: 4),
        if (profiles.isNotEmpty)
          ysMenuItem('shell:$kPlatformDefaultShellId', FLucideIcons.terminal,
              'Platform default shell'),
        for (final s in profiles)
          ysMenuItem('shell:${s.id}', FLucideIcons.terminal, s.name),
      ],
    );
    if (result == null) return;
    if (result == 'ssh') {
      onNewSsh();
    } else if (result == 'local') {
      onNewLocal();
    } else if (result == 'shell:$kPlatformDefaultShellId') {
      onNewLocal(platformDefault: true);
    } else if (result.startsWith('shell:')) {
      final id = result.substring('shell:'.length);
      onNewLocal(profile: profiles.firstWhere((s) => s.id == id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'New tab',
      child: SizedBox(
        width: 36,
        height: YsTab.height,
        child: Center(
          child: FButton.icon(
            variant: .ghost,
            size: .xs,
            onPress: () => _showAddMenu(context),
            child: const Icon(FLucideIcons.plus, size: 16),
          ),
        ),
      ),
    );
  }
}
