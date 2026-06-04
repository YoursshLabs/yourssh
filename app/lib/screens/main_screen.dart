import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/workspace_service.dart';
import '../models/host.dart';
import '../models/known_host.dart';
import '../models/local_session.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../models/session_health.dart';
import '../services/health_monitor_service.dart';
import '../providers/host_provider.dart';
import '../providers/known_hosts_provider.dart';
import '../providers/session_provider.dart';
import '../providers/recording_provider.dart';
import '../main.dart' show kAppVersion;
import '../theme/app_theme.dart';
import '../widgets/health_dot.dart';
import '../widgets/host_detail_panel.dart';
import '../widgets/hosts_dashboard.dart';
import '../widgets/keychain_screen.dart';
import '../widgets/known_hosts_screen.dart';
import '../widgets/port_forwarding_screen.dart';
import '../widgets/settings_screen.dart';
import '../widgets/network_stats_overlay.dart';
import '../widgets/dual_panel_sftp_screen.dart';
import '../widgets/keep_alive_offstage.dart';
import '../widgets/split_terminal_view.dart';
import '../widgets/new_group_panel.dart';
import '../widgets/import_panel.dart';
import '../widgets/ai_chat_sidebar.dart';
import '../widgets/command_palette.dart';
import '../widgets/plugin_consent_dialog.dart';
import '../widgets/plugin_manager_screen.dart';
import '../widgets/recording_library_screen.dart';
import '../plugins/plugin_context_impl.dart';
import '../providers/plugin_engine_provider.dart';
import '../providers/plugin_provider.dart';
import '../services/ssh_service.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:path/path.dart' as p;
import '../providers/settings_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../services/hotkey_service.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../widgets/script_plugin_panel_screen.dart';
import '../providers/share_provider.dart';
import '../widgets/share_session_dialog.dart';
import '../widgets/join_share_dialog.dart';
import '../widgets/update_banner.dart';
import '../widgets/notification_bell.dart';

enum NavSection { hosts, keychain, portForwarding, sftp, knownHosts, recordings, settings, plugins }

enum _SidePanel { none, host, newGroup, import }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final _workspaceSvc = WorkspaceService();
  Timer? _workspaceSaveDebounce;
  NavSection _nav = NavSection.hosts;
  String? _activePluginId;
  String? _activeScriptPanel;
  bool _pluginResetScheduled = false;
  _SidePanel _sidePanel = _SidePanel.none;
  final Map<String, PluginContextImpl> _pluginContexts = {};
  Host? _editingHost;
  String? _initialGroup;
  bool _viewingTerminal = false;
  bool _showAiChat = false;
  final _sftpConnectionNotifier = ValueNotifier<bool>(false);
  SessionProvider? _sessionProvider;
  KnownHostsProvider? _knownHostsProvider;
  SettingsProvider? _settingsProvider;
  TerminalLayoutProvider? _layoutProvider;
  bool _hostKeyDialogShowing = false;
  bool _consentDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreWorkspace());
    _sftpConnectionNotifier.addListener(_onSftpConnectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wirePluginLifecycle();
      _wireRecordingErrors();
    });
  }

  void _showUpdateDetails() => setState(() {
        _activePluginId = null;
        _activeScriptPanel = null;
        _nav = NavSection.settings;
        _viewingTerminal = false;
        _showAiChat = false;
      });

  void _wireRecordingErrors() {
    if (!mounted) return;
    context.read<RecordingProvider>().onStartFailed = (session, error) {
      if (!mounted) return;
      AppSnack.error(context, 'Recording failed for ${session.tabLabel}: $error');
    };
  }

  void _wirePluginLifecycle() {
    if (!mounted) return;
    final pluginProvider = context.read<PluginProvider>();
    // Catch per-plugin so one buggy plugin can't take down the whole toggle.
    pluginProvider.onToggled = (plugin, enabled) {
      try {
        if (enabled) {
          plugin.onActivate(_pluginContext(plugin.id));
        } else {
          plugin.onDeactivate();
        }
      } catch (e, st) {
        debugPrint('[plugin ${plugin.id}] lifecycle error: $e\n$st');
      }
    };
    // Fire onActivate for plugins already enabled at startup (prefs already loaded).
    for (final plugin in pluginProvider.enabledPlugins) {
      try {
        plugin.onActivate(_pluginContext(plugin.id));
      } catch (e, st) {
        debugPrint('[plugin ${plugin.id}] onActivate error: $e\n$st');
      }
    }
  }

  Future<void> _registerHotkeys(Map<String, String> hotkeys) async {
    final svc = HotkeyService();
    await svc.unregisterAll();
    for (final entry in hotkeys.entries) {
      final hotKey = HotkeyService.parse(entry.value);
      if (hotKey == null) continue;
      await svc.register(entry.key, hotKey, () => _handleHotkey(entry.key));
    }
  }

  void _handleHotkey(String name) {
    if (!mounted) return;
    switch (name) {
      case 'new_session':
        _openHostPanel();
      case 'close_session':
        context.read<SessionProvider>().closeActive();
      case 'next_session':
        context.read<SessionProvider>().activateNext();
      case 'prev_session':
        context.read<SessionProvider>().activatePrev();
      case 'toggle_input_bar':
        context.read<TerminalLayoutProvider>().toggleInputBar();
      case 'split_horizontal':
        context.read<TerminalLayoutProvider>().setLayout(SplitLayout.horizontal);
      case 'split_vertical':
        context.read<TerminalLayoutProvider>().setLayout(SplitLayout.vertical);
      case 'command_palette':
        _openCommandPalette();
    }
  }

  void _onSftpConnectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<SessionProvider>();
    if (_sessionProvider != provider) {
      _sessionProvider?.removeListener(_onSessionsChanged);
      _sessionProvider?.removeListener(_onSessionsChangedForSave);
      _sessionProvider = provider;
      provider.addListener(_onSessionsChanged);
      provider.addListener(_onSessionsChangedForSave);
    }
    final settings = context.read<SettingsProvider>();
    if (_settingsProvider != settings) {
      _settingsProvider?.removeListener(_onSettingsChanged);
      _settingsProvider = settings;
      settings.addListener(_onSettingsChanged);
      _registerHotkeys(settings.hotkeys);
    }
    final knownHostsProvider = context.read<KnownHostsProvider>();
    if (_knownHostsProvider != knownHostsProvider) {
      _knownHostsProvider?.removeListener(_onKnownHostsChanged);
      _knownHostsProvider = knownHostsProvider;
      knownHostsProvider.addListener(_onKnownHostsChanged);
    }
    final layout = context.read<TerminalLayoutProvider>();
    if (_layoutProvider != layout) {
      _layoutProvider?.removeListener(_onLayoutChangedForSave);
      _layoutProvider = layout;
      layout.addListener(_onLayoutChangedForSave);
    }
  }

  void _onSettingsChanged() {
    if (_settingsProvider != null) {
      _registerHotkeys(_settingsProvider!.hotkeys);
    }
  }

  void _onKnownHostsChanged() {
    final challenge = _knownHostsProvider?.pendingChallenge;
    if (challenge != null && !_hostKeyDialogShowing && mounted) {
      _hostKeyDialogShowing = true;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HostKeyDialog(challenge: challenge),
      ).then((trusted) {
        challenge.resolve(trusted ?? false);
        _hostKeyDialogShowing = false;
      });
    }
  }

  void _onSessionsChanged() {
    if (!mounted) return;
    final sessions = _sessionProvider?.sessions ?? [];
    if (sessions.isNotEmpty && !_viewingTerminal) {
      setState(() => _viewingTerminal = true);
    } else if (sessions.isEmpty && _viewingTerminal) {
      setState(() => _viewingTerminal = false);
    }
  }

  void _onLayoutChangedForSave() => _scheduleSave();
  void _onSessionsChangedForSave() => _scheduleSave();

  void _scheduleSave() {
    _workspaceSaveDebounce?.cancel();
    _workspaceSaveDebounce = Timer(
      const Duration(milliseconds: 500),
      _saveWorkspaceNow,
    );
  }

  void _saveWorkspaceNow() {
    // SSH tabs only — local sessions are ephemeral by design.
    final sessions = _sessionProvider?.sshSessions;
    final layout = _layoutProvider;
    if (sessions == null || layout == null) return;
    final active = _sessionProvider?.activeSession;
    final snapshot = WorkspaceSnapshot(
      hostIds: sessions.map((s) => s.host.id).toList(),
      activeHostId: active is SshSession ? active.host.id : null,
      layout: layout.layout,
      inputBarVisible: layout.inputBarVisible,
    );
    _workspaceSvc.save(snapshot);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) _saveWorkspaceNow();
  }

  @override
  void dispose() {
    _sftpConnectionNotifier.removeListener(_onSftpConnectionChanged);
    _sftpConnectionNotifier.dispose();
    _sessionProvider?.removeListener(_onSessionsChanged);
    _sessionProvider?.removeListener(_onSessionsChangedForSave);
    _knownHostsProvider?.removeListener(_onKnownHostsChanged);
    _settingsProvider?.removeListener(_onSettingsChanged);
    _layoutProvider?.removeListener(_onLayoutChangedForSave);
    WidgetsBinding.instance.removeObserver(this);
    _workspaceSaveDebounce?.cancel();
    HotkeyService().unregisterAll();
    super.dispose();
  }

  void _openHostPanel({Host? existing, String? initialGroup}) {
    setState(() {
      _sidePanel = _SidePanel.host;
      _editingHost = existing;
      _initialGroup = initialGroup;
    });
  }

  /// Sidebar "Local Terminal" + command palette entry: focus the last local
  /// tab if one exists (list order approximates recency), else open a new one.
  void _openLocalTerminal() {
    final provider = context.read<SessionProvider>();
    final existing = provider.sessions.whereType<LocalSession>().lastOrNull;
    if (existing != null) {
      provider.setActive(existing.id);
    } else {
      unawaited(provider.newLocalSession());
    }
    setState(() => _viewingTerminal = true);
  }

  void _openNewGroupPanel() => setState(() {
        _sidePanel = _SidePanel.newGroup;
        _editingHost = null;
        _initialGroup = null;
      });

  void _openImportPanel() => setState(() {
        _sidePanel = _SidePanel.import;
        _editingHost = null;
        _initialGroup = null;
      });

  void _closePanel() => setState(() {
        _sidePanel = _SidePanel.none;
        _editingHost = null;
        _initialGroup = null;
      });

  Future<void> _restoreWorkspace() async {
    final snapshot = await _workspaceSvc.load();
    if (snapshot == null || !mounted) return;

    final hostProvider = context.read<HostProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final layoutProvider = context.read<TerminalLayoutProvider>();

    final allHosts = hostProvider.allHosts;
    final found = snapshot.hostIds
        .map((id) => allHosts.where((h) => h.id == id).firstOrNull)
        .whereType<Host>()
        .toList();

    final missingCount = snapshot.hostIds.length - found.length;
    if (missingCount > 0 && mounted) {
      AppSnack.info(context,
          '$missingCount host(s) from last session no longer exist');
    }

    if (found.isEmpty) {
      await _workspaceSvc.clear();
      return;
    }

    layoutProvider.setLayout(snapshot.layout);
    if (snapshot.inputBarVisible != layoutProvider.inputBarVisible) {
      layoutProvider.toggleInputBar();
    }

    for (final host in found) {
      unawaited(sessionProvider.connect(host));
    }

    // Sessions are added synchronously at connect() entry; set active now.
    if (snapshot.activeHostId != null) {
      final targetSession = sessionProvider.sshSessions
          .where((s) => s.host.id == snapshot.activeHostId)
          .firstOrNull;
      if (targetSession != null) {
        sessionProvider.setActive(targetSession.id);
      }
    }

    await _workspaceSvc.clear();
  }

  void _openCommandPalette() {
    final hosts = context.read<HostProvider>().allHosts;
    final canShare = context.read<ShareProvider>().canShare;

    final items = <CommandItem>[
      // Actions
      CommandItem(
        id: 'action_new_host',
        title: 'New Host',
        subtitle: 'Add a new SSH connection',
        icon: Icons.add_circle_outline,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openHostPanel()),
      ),
      CommandItem(
        id: 'action_import',
        title: 'Import SSH Config',
        subtitle: 'Import from ~/.ssh/config',
        icon: Icons.upload_file_outlined,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openImportPanel()),
      ),
      if (canShare)
        CommandItem(
          id: 'action_join_share',
          title: 'Join Shared Session',
          subtitle: 'Watch a colleague\'s terminal using a share code',
          icon: Icons.screen_share_outlined,
          type: CommandType.action,
          execute: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => showDialog(context: context, builder: (_) => const JoinShareDialog()),
          ),
        ),
      // Nav sections
      CommandItem(
        id: 'nav_hosts',
        title: 'Hosts',
        subtitle: 'Manage SSH connections',
        icon: Icons.dns_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.hosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_sftp',
        title: 'SFTP',
        subtitle: 'File transfer',
        icon: Icons.folder_open,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.sftp; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_keychain',
        title: 'Keychain',
        subtitle: 'SSH keys',
        icon: Icons.vpn_key_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.keychain; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_port_forwarding',
        title: 'Port Forwarding',
        subtitle: 'Tunnel rules',
        icon: Icons.swap_horiz,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.portForwarding; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_local_terminal',
        title: 'Local Terminal',
        subtitle: 'Local shell',
        icon: Icons.laptop_mac,
        type: CommandType.navSection,
        execute: _openLocalTerminal,
      ),
      CommandItem(
        id: 'nav_recordings',
        title: 'Recordings',
        subtitle: 'Session recordings',
        icon: Icons.video_library_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.recordings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_known_hosts',
        title: 'Known Hosts',
        subtitle: 'Host key verification',
        icon: Icons.fact_check_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.knownHosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_settings',
        title: 'Settings',
        subtitle: 'App preferences',
        icon: Icons.settings_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.settings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_plugins',
        title: 'Plugins',
        subtitle: 'Plugin marketplace',
        icon: Icons.extension_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.plugins; _viewingTerminal = false; }),
      ),
      // Hosts
      ...hosts.map((h) => CommandItem(
        id: 'host_${h.id}',
        title: h.label,
        subtitle: '${h.username}@${h.host}:${h.port}',
        icon: Icons.dns,
        type: CommandType.host,
        execute: () async {
          setState(() => _viewingTerminal = true);
          await context.read<SessionProvider>().connect(h);
        },
      )),
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPaletteDialog(items: items),
    );
  }

  PluginContextImpl _pluginContext(String pluginId) {
    return _pluginContexts.putIfAbsent(pluginId, () => PluginContextImpl(
      sessions: context.read<SessionProvider>(),
      ssh: context.read<SshService>(),
      pluginId: pluginId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.watch<SessionProvider>();
    final sessions = sessionProvider.sessions;
    final activeSession = sessionProvider.activeSession;

    final engineProvider = context.watch<PluginEngineProvider>();
    if (engineProvider.pendingConsent != null && !_consentDialogShowing) {
      _consentDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              PluginConsentDialog(manifest: engineProvider.pendingConsent!),
        ).then((_) => setState(() => _consentDialogShowing = false));
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _TopTabBar(
            sessions: sessions,
            active: activeSession,
            nav: _nav,
            viewingTerminal: _viewingTerminal && sessions.isNotEmpty,
            onNavSelect: (s) => setState(() {
              _activePluginId = null;
              _activeScriptPanel = null;
              _nav = s;
              _viewingTerminal = false;
              _showAiChat = false;
              if (s != NavSection.hosts) _closePanel();
            }),
            onSessionTap: (_) => setState(() => _viewingTerminal = true),
            onAddSession: () {
              setState(() {
                _activePluginId = null;
                _activeScriptPanel = null;
                _nav = NavSection.hosts;
                _viewingTerminal = false;
                _showAiChat = false;
              });
              _openHostPanel();
            },
            onAddLocalSession: () {
              setState(() => _viewingTerminal = true);
              unawaited(context.read<SessionProvider>().newLocalSession());
            },
            onShowUpdateDetails: _showUpdateDetails,
            onOpenSession: (sessionId) {
              final sp = context.read<SessionProvider>();
              if (sp.sessions.any((s) => s.id == sessionId)) {
                sp.setActive(sessionId);
                setState(() => _viewingTerminal = true);
              }
            },
          ),
          UpdateBanner(onShowDetails: _showUpdateDetails),

          Expanded(
            child: Row(
              children: [
                if ((!_viewingTerminal || sessions.isEmpty) &&
                    !(_nav == NavSection.sftp && _sftpConnectionNotifier.value))
                  _Sidebar(
                    selected: _nav,
                    activePluginId: _activePluginId,
                    onOpenLocalTerminal: _openLocalTerminal,
                    onSelect: (s) {
                      if (s != NavSection.hosts) _closePanel();
                      setState(() {
                        _activePluginId = null;
                        _activeScriptPanel = null;
                        _nav = s;
                        _viewingTerminal = false;
                        _showAiChat = false;
                      });
                    },
                    onSelectPlugin: (id) {
                      setState(() {
                        _activePluginId = id;
                        _viewingTerminal = false;
                        _sidePanel = _SidePanel.none;
                      });
                    },
                    activeScriptPanel: _activeScriptPanel,
                    onSelectScriptPanel: (pluginId) {
                      setState(() {
                        _activeScriptPanel = pluginId;
                        _activePluginId = null;
                        _viewingTerminal = false;
                        _sidePanel = _SidePanel.none;
                      });
                    },
                  ),
                Expanded(child: _buildContent(activeSession)),
                if (_nav == NavSection.hosts && !_viewingTerminal) ...[
                  if (_sidePanel == _SidePanel.host)
                    HostDetailPanel(
                      existing: _editingHost,
                      initialGroup: _initialGroup,
                      onClose: _closePanel,
                      onSave: (host, password) async {
                        final hp = context.read<HostProvider>();
                        if (_editingHost != null) {
                          await hp.updateHost(host, password: password);
                        } else {
                          await hp.addHost(host, password: password);
                        }
                      },
                      onConnect: (host) async {
                        setState(() => _viewingTerminal = true);
                        await context.read<SessionProvider>().connect(host);
                      },
                    ),
                  if (_sidePanel == _SidePanel.newGroup)
                    NewGroupPanel(onClose: _closePanel),
                  if (_sidePanel == _SidePanel.import)
                    ImportPanel(onClose: _closePanel),
                ],
              ],
            ),
          ),
          Consumer<PluginUiRegistry>(
            builder: (context, registry, _) {
              if (registry.statusBarItems.isEmpty) return const SizedBox.shrink();
              return Container(
                height: 24,
                color: AppColors.sidebar,
                child: Row(
                  children: [
                    for (final item in registry.statusBarItems)
                      Tooltip(
                        message: item.tooltip ?? '',
                        child: InkWell(
                          onTap: item.onClick,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              item.label,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(TerminalSession? active) {
    final showSftp = _nav == NavSection.sftp &&
        !(_viewingTerminal && active != null) &&
        _activePluginId == null &&
        _activeScriptPanel == null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // SFTP stays mounted (offstage) once opened so its connected session,
        // paths, and in-flight transfers survive switching tabs (issue #42).
        KeepAliveOffstage(
          active: showSftp,
          child: DualPanelSftpScreen(
            connectionNotifier: _sftpConnectionNotifier,
            active: showSftp,
          ),
        ),
        if (!showSftp) _buildForeground(active),
      ],
    );
  }

  Widget _buildForeground(TerminalSession? active) {
    if (_viewingTerminal && active != null) {
      return Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                const SplitTerminalView(),
                Positioned(
                  top: 8,
                  right: _showAiChat ? 348 : 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const NetworkStatsOverlay(),
                      const SizedBox(width: 8),
                      if (active is SshSession) ...[
                        _ShareButton(session: active),
                        const SizedBox(width: 8),
                      ],
                      _AiChatToggle(
                        active: _showAiChat,
                        onToggle: () => setState(() => _showAiChat = !_showAiChat),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_showAiChat)
            AiChatSidebar(
              onClose: () => setState(() => _showAiChat = false),
            ),
        ],
      );
    }

    // Script plugin panel
    if (_activeScriptPanel != null) {
      final registry = context.watch<PluginUiRegistry>();
      final panels = registry.panels.where((p) => p.pluginId == _activeScriptPanel);
      if (panels.isNotEmpty) {
        return ScriptPluginPanelScreen(panel: panels.first);
      }
      if (!_pluginResetScheduled) {
        _pluginResetScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pluginResetScheduled = false;
          if (mounted) setState(() => _activeScriptPanel = null);
        });
      }
      return const SizedBox.shrink();
    }

    // Active plugin view
    if (_activePluginId != null) {
      final pluginProvider = context.watch<PluginProvider>(); // watch so disable triggers rebuild
      final enabled = pluginProvider.enabledPlugins.where((p) => p.id == _activePluginId);
      if (enabled.isNotEmpty) {
        final plugin = enabled.first;
        return _PluginErrorBoundary(
          key: ValueKey(plugin.id),
          plugin: plugin,
          pluginCtx: _pluginContext(plugin.id),
        );
      }
      // Plugin was disabled while viewing it — reset once after this frame.
      // Without the guard, the post-frame callback re-runs every build, causing
      // an infinite rebuild loop until the plugin re-enables.
      if (!_pluginResetScheduled) {
        _pluginResetScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pluginResetScheduled = false;
          if (mounted) setState(() => _activePluginId = null);
        });
      }
      return const SizedBox.shrink();
    }

    return switch (_nav) {
      NavSection.hosts => HostsDashboard(
          onAddHost: () => _openHostPanel(),
          onEditHost: (h) => _openHostPanel(existing: h),
          onOpenLocalTerminal: _openLocalTerminal,
          onNewGroup: _openNewGroupPanel,
          onImport: _openImportPanel,
        ),
      NavSection.keychain => const KeychainScreen(),
      NavSection.portForwarding => const PortForwardingScreen(),
      // Rendered by the KeepAliveOffstage layer in _buildContent.
      NavSection.sftp => const SizedBox.shrink(),
      NavSection.recordings => const RecordingLibraryScreen(),
      NavSection.knownHosts => const KnownHostsScreen(),
      NavSection.settings => const SettingsScreen(),
      NavSection.plugins => const PluginManagerScreen(),
    };
  }
}

// ── Sidebar ───────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final NavSection selected;
  final String? activePluginId;
  final String? activeScriptPanel;
  final ValueChanged<NavSection> onSelect;
  final ValueChanged<String> onSelectPlugin;
  final ValueChanged<String> onSelectScriptPanel;
  final VoidCallback onOpenLocalTerminal;
  const _Sidebar({
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
    return Container(
      width: 200,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: AppColors.textSecondary, size: 16),
                const SizedBox(width: 8),
                const Text('YourSSH',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),

          // Scrollable nav area so the sidebar never overflows when the
          // window is short or many plugin/script panels are enabled.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          const _SectionLabel('CONNECTIONS'),
          _navItem(Icons.dns_outlined, 'Hosts', NavSection.hosts),
          _navItem(Icons.swap_horiz, 'Port Forwarding', NavSection.portForwarding),
          _navItem(Icons.fact_check_outlined, 'Known Hosts', NavSection.knownHosts),

          const _SectionLabel('FILES & TRANSFER'),
          _navItem(Icons.folder_open, 'SFTP', NavSection.sftp),

          const _SectionLabel('TOOLS'),
          // Action, not a nav target: local terminal lives in the top tab bar.
          _NavItem(
            icon: Icons.laptop_mac,
            label: 'Local Terminal',
            selected: false,
            onTap: onOpenLocalTerminal,
          ),
          _navItem(Icons.video_library_outlined, 'Recordings', NavSection.recordings),
          ...context.watch<PluginProvider>().enabledPlugins.map(
            (plugin) => _pluginNavItem(context, plugin),
          ),
          ...context.watch<PluginUiRegistry>().panels.map(
            (panel) => _ScriptPanelNavItem(
              panel: panel,
              isActive: activeScriptPanel == panel.pluginId,
              onTap: () => onSelectScriptPanel(panel.pluginId),
            ),
          ),

          const _SectionLabel('SECURITY'),
          _navItem(Icons.vpn_key_outlined, 'Keychain', NavSection.keychain),

                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _navItem(Icons.extension_outlined, 'Plugins', NavSection.plugins),
          _navItem(Icons.settings_outlined, 'Settings', NavSection.settings),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YourSSH', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                    Text('v$kAppVersion', style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, NavSection section) {
    final isSelected = activePluginId == null && selected == section;
    return _NavItem(icon: icon, label: label, selected: isSelected, onTap: () => onSelect(section));
  }

  Widget _pluginNavItem(BuildContext context, YourSSHPlugin plugin) {
    return _PluginNavItem(
      plugin: plugin,
      isActive: activePluginId == plugin.id,
      onTap: () => onSelectPlugin(plugin.id),
    );
  }
}

class _PluginNavItem extends StatefulWidget {
  final YourSSHPlugin plugin;
  final bool isActive;
  final VoidCallback onTap;
  const _PluginNavItem({required this.plugin, required this.isActive, required this.onTap});

  @override
  State<_PluginNavItem> createState() => _PluginNavItemState();
}

class _PluginNavItemState extends State<_PluginNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final iconColor = widget.isActive ? AppColors.accent : AppColors.textSecondary;
    final textColor = widget.isActive ? AppColors.accent : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.isActive ? Border.all(color: AppColors.accent.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.plugin.icon, size: 15, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.plugin.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScriptPanelNavItem extends StatelessWidget {
  final PluginPanelEntry panel;
  final bool isActive;
  final VoidCallback onTap;

  const _ScriptPanelNavItem({
    required this.panel,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _NavItem(
      icon: Icons.code_outlined,
      label: panel.title,
      selected: isActive,
      onTap: onTap,
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final iconColor = widget.selected ? AppColors.accent : AppColors.textSecondary;
    final textColor = widget.selected ? AppColors.accent : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.selected ? Border.all(color: AppColors.accent.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: iconColor),
              const SizedBox(width: 10),
              Text(widget.label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: widget.selected ? FontWeight.w500 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top Tab Bar ───────────────────────────────────────────

class _TopTabBar extends StatelessWidget {
  final List<TerminalSession> sessions;
  final TerminalSession? active;
  final NavSection nav;
  final bool viewingTerminal;
  final ValueChanged<NavSection> onNavSelect;
  final ValueChanged<String> onSessionTap;
  final VoidCallback onAddSession;
  final VoidCallback onAddLocalSession;
  final VoidCallback onShowUpdateDetails;
  final ValueChanged<String> onOpenSession;

  const _TopTabBar({
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
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          // Pinned nav shortcuts
          _PinnedTab(
            icon: Icons.home_outlined,
            label: 'Home',
            active: nav == NavSection.hosts && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.hosts),
          ),
          _PinnedTab(
            icon: Icons.folder_outlined,
            label: 'SFTP',
            active: nav == NavSection.sftp && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.sftp),
          ),
          // Divider
          Container(width: 1, height: 18, color: const Color(0xFF2A2A2A)),
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
                  child: _SessionTab(
                    session: s,
                    isActive: s.id == active?.id && viewingTerminal,
                    provider: provider,
                    onTap: () => onSessionTap(s.id),
                  ),
                );
              },
            ),
          ),
          // "+" button
          _AddTabBtn(onNewSsh: onAddSession, onNewLocal: onAddLocalSession),
          NotificationBellBtn(
            onShowUpdateDetails: onShowUpdateDetails,
            onOpenSession: onOpenSession,
          ),
        ],
      ),
    );
  }
}

class _PinnedTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PinnedTab({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  State<_PinnedTab> createState() => _PinnedTabState();
}

class _PinnedTabState extends State<_PinnedTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? AppColors.accent
        : _hovered
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: widget.active
                ? const Border(bottom: BorderSide(color: AppColors.accent, width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: widget.active ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTab extends StatefulWidget {
  final TerminalSession session;
  final bool isActive;
  final SessionProvider provider;
  final VoidCallback onTap;
  const _SessionTab({required this.session, required this.isActive, required this.provider, required this.onTap});

  @override
  State<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<_SessionTab> {
  bool _hovered = false;
  bool _isRenaming = false;
  late TextEditingController _renameController;

  @override
  void initState() {
    super.initState();
    _renameController = TextEditingController();
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  void _startRename() {
    _renameController.text = widget.session.tabLabel;
    _renameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _renameController.text.length,
    );
    setState(() => _isRenaming = true);
  }

  void _commitRename() {
    final text = _renameController.text.trim();
    widget.provider.renameSession(
      widget.session.id,
      text.isEmpty ? null : text,
    );
    setState(() => _isRenaming = false);
  }

  /// Tab label, appending the shell-integration cwd basename when known and
  /// the user hasn't set a custom label.
  String _composedLabel(BuildContext context) {
    final base = widget.session.tabLabel;
    if (widget.session.customLabel != null) return base;
    // select scopes the rebuild to this session's cwd (provider notifies globally).
    final cwd = context.select<ShellIntegrationProvider, String?>(
        (s) => s.cwdFor(widget.session.id));
    if (cwd == null || cwd.isEmpty) return base;
    final name = p.posix.basename(cwd);
    return '$base · ${name.isEmpty ? '/' : name}';
  }

  Future<void> _showTabContextMenu(BuildContext context, Offset globalPos) async {
    final session = widget.session;
    final provider = widget.provider;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: const Row(children: [
            Icon(Icons.edit_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('Rename', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Row(children: [
            Icon(
              session.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 14,
              color: const Color(0xFFAAAAAA),
            ),
            const SizedBox(width: 8),
            Text(
              session.isPinned ? 'Unpin' : 'Pin',
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
            ),
          ]),
        ),
        PopupMenuItem(
          value: 'color',
          child: const Row(children: [
            Icon(Icons.circle_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('Color tag', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
            Spacer(),
            Icon(Icons.chevron_right, size: 14, color: Color(0xFF666666)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          child: const Row(children: [
            Icon(Icons.close, size: 14, color: Color(0xFF888888)),
            SizedBox(width: 8),
            Text('Close', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
          ]),
        ),
      ],
    );

    if (!context.mounted) return;

    switch (result) {
      case 'rename':
        _startRename();
      case 'pin':
        provider.togglePin(session.id);
      case 'color':
        await _showColorSubmenu(context, globalPos);
      case 'close':
        provider.closeSession(session.id);
    }
  }

  Future<void> _showColorSubmenu(BuildContext context, Offset globalPos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx + 160, globalPos.dy + 60,
        globalPos.dx + 161, globalPos.dy + 61,
      ),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          value: 'none',
          child: const Row(children: [
            SizedBox(
              width: 14, height: 14,
              child: Icon(Icons.block, size: 12, color: Color(0xFF666666)),
            ),
            SizedBox(width: 8),
            Text('None', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
          ]),
        ),
        ...AppColors.tabColors.map((c) => PopupMenuItem(
          value: c.$2,
          child: Row(children: [
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: AppColors.fromHex(c.$2),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(c.$1, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        )),
      ],
    );

    if (result != null) {
      widget.provider.setSessionColor(
        widget.session.id,
        result == 'none' ? null : result,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = widget.isActive ? AppColors.accent : const Color(0xFF888888);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          widget.provider.setActive(widget.session.id);
          widget.onTap();
        },
        onDoubleTap: _startRename,
        onSecondaryTapUp: (details) =>
            _showTabContextMenu(context, details.globalPosition),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFF1C1C1C)
                : _hovered
                    ? const Color(0xFF141414)
                    : Colors.transparent,
            border: widget.isActive
                ? const Border(bottom: BorderSide(color: AppColors.accent, width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Connection health dot for SSH (hidden for watch sessions);
              // laptop glyph for local tabs.
              if (widget.session case final SshSession ssh
                  when !ssh.isWatch)
                Builder(builder: (context) {
                  final health = context
                      .watch<HealthMonitorService>()
                      .healthFor(ssh.host.id);
                  final tone = badgeToneFor(ssh.status, health);
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Tooltip(
                      message: _healthTooltip(ssh, health),
                      child: HealthDot(tone: tone),
                    ),
                  );
                })
              else if (widget.session.isLocal)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(Icons.laptop_mac,
                      size: 12, color: Color(0xFF888888)),
                ),
              // Red recording indicator
              Consumer<RecordingProvider>(
                builder: (context, rec, _) => rec.isRecording(widget.session.id)
                    ? Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // Color dot (shown when colorTag is set)
              if (widget.session.colorTag != null)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: AppColors.fromHex(widget.session.colorTag!),
                    shape: BoxShape.circle,
                  ),
                ),
              // X close button — hidden when pinned
              if (!widget.session.isPinned)
                GestureDetector(
                  onTap: () => widget.provider.closeSession(widget.session.id),
                  child: Icon(
                    Icons.close,
                    size: 11,
                    color: _hovered || widget.isActive ? const Color(0xFF888888) : const Color(0xFF444444),
                  ),
                ),
              const SizedBox(width: 8),
              // Host label — switches to Focus+TextField when renaming
              if (_isRenaming)
                SizedBox(
                  width: 100,
                  height: 20,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        setState(() => _isRenaming = false);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _renameController,
                      autofocus: true,
                      style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _commitRename(),
                      onTapOutside: (_) => _commitRename(),
                      // Suppress default focus-traversal on Enter; commit is
                      // handled by onSubmitted/onTapOutside.
                      onEditingComplete: () {},
                    ),
                  ),
                )
              else
                Text(
                  _composedLabel(context),
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              const SizedBox(width: 8),
              // Pin icon (shown when pinned)
              if (widget.session.isPinned)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.push_pin, size: 11, color: Color(0xFF888888)),
                ),
              // Terminal icon (right)
              Icon(
                Icons.monitor_outlined,
                size: 13,
                color: widget.isActive ? AppColors.accent : const Color(0xFF555555),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTabBtn extends StatefulWidget {
  final VoidCallback onNewSsh;
  final VoidCallback onNewLocal;
  const _AddTabBtn({required this.onNewSsh, required this.onNewLocal});

  @override
  State<_AddTabBtn> createState() => _AddTabBtnState();
}

class _AddTabBtnState extends State<_AddTabBtn> {
  bool _hovered = false;

  Future<void> _showAddMenu() async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height));
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        const PopupMenuItem(
          value: 'ssh',
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('New SSH session',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        const PopupMenuItem(
          value: 'local',
          child: Row(children: [
            Icon(Icons.laptop_mac, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('New local terminal',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
      ],
    );
    switch (result) {
      case 'ssh':
        widget.onNewSsh();
      case 'local':
        widget.onNewLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _showAddMenu,
        child: Container(
          width: 36,
          height: 38,
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 16,
            color: _hovered ? const Color(0xFFAAAAAA) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

// ── AI Chat Toggle Button ─────────────────────────────────

class _AiChatToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;

  const _AiChatToggle({required this.active, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Close AI Chat' : 'Open AI Chat',
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.card.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 14,
                color: active ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                'AI',
                style: TextStyle(
                  color: active ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Host Key Mismatch Dialog ──────────────────────────────

class _HostKeyDialog extends StatelessWidget {
  final HostKeyChallenge challenge;
  const _HostKeyDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('Host key changed',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${challenge.host}:${challenge.port}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          _FpRow(label: 'Old', fp: challenge.oldFingerprint),
          const SizedBox(height: 4),
          _FpRow(label: 'New', fp: challenge.newFingerprint),
          const SizedBox(height: 12),
          const Text(
            'This could indicate a man-in-the-middle attack. '
            'Only trust the new key if you know the server key changed.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
          child: const Text('Trust new key'),
        ),
      ],
    );
  }
}

// ── Plugin Error Boundary ─────────────────────────────────

class _PluginErrorBoundary extends StatefulWidget {
  final YourSSHPlugin plugin;
  final PluginContextImpl pluginCtx;
  const _PluginErrorBoundary({super.key, required this.plugin, required this.pluginCtx});

  @override
  State<_PluginErrorBoundary> createState() => _PluginErrorBoundaryState();
}

class _PluginErrorBoundaryState extends State<_PluginErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 12),
              Text(
                'Plugin crashed: $_error',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    try {
      return widget.plugin.buildUI(context, widget.pluginCtx);
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _error = e);
      });
      return const SizedBox.shrink();
    }
  }

  @override
  void didUpdateWidget(_PluginErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin.id != widget.plugin.id) _error = null;
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _FpRow extends StatelessWidget {
  final String label;
  final String fp;
  const _FpRow({required this.label, required this.fp});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text('$label:',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: Text(fp,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  final SshSession session;
  const _ShareButton({required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    if (!share.canShare || session.isWatch) return const SizedBox.shrink();
    if (session.status != SessionStatus.connected) return const SizedBox.shrink();

    final isActive = share.isSharing;
    return Tooltip(
      message: isActive ? 'Sharing active' : 'Share this terminal',
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => ShareSessionDialog(sessionId: session.id),
        ),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? AppColors.accent : const Color(0xFF2A2A2A),
            ),
          ),
          child: Icon(
            Icons.screen_share_outlined,
            size: 14,
            color: isActive ? AppColors.accent : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

String _healthTooltip(SshSession session, SessionHealth health) {
  final latency = health.latencyMs != null ? '${health.latencyMs}ms' : '—';
  final word = switch (health.status) {
    HealthStatus.healthy => 'healthy',
    HealthStatus.degraded => 'degraded',
    HealthStatus.down => 'down',
    HealthStatus.offline => 'connecting…',
  };
  final uptime = _fmtDuration(DateTime.now().difference(session.connectedAt));
  final ping = health.lastPingAt != null
      ? '${DateTime.now().difference(health.lastPingAt!).inSeconds}s ago'
      : '—';
  return '${session.title}\n'
      '$latency · $word\n'
      'Uptime $uptime · last ping $ping\n'
      'Reconnects this session: ${session.reconnectCount}';
}

String _fmtDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
