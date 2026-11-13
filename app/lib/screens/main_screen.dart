import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/safe_set_state.dart';
import '../services/workspace_service.dart';
import '../models/host.dart';
import '../models/local_session.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/ai_chat_provider.dart';
import '../providers/host_provider.dart';
import '../providers/known_hosts_provider.dart';
import '../providers/session_provider.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';
import 'shell/app_sidebar.dart';
import 'shell/session_tab_bar.dart';
import '../widgets/plugin_status_bar_item.dart';
import '../widgets/host_detail_panel.dart';
import '../widgets/hosts_dashboard.dart';
import '../widgets/keychain_screen.dart';
import '../widgets/rdp_password_dialog.dart';
import '../widgets/known_hosts_screen.dart';
import '../widgets/port_forwarding_screen.dart';
import '../widgets/settings_screen.dart';
import '../widgets/terminal_header_actions.dart';
import '../widgets/dual_panel_sftp_screen.dart';
import '../widgets/keep_alive_offstage.dart';
import '../widgets/split_terminal_view.dart';
import '../widgets/new_group_panel.dart';
import '../widgets/import_panel.dart';
import '../widgets/ai_chat_sidebar.dart';
import '../widgets/command_palette.dart';
import '../widgets/plugin_consent_dialog.dart';
import '../widgets/tofu_dialogs.dart';
import '../widgets/plugin_manager_screen.dart';
import '../widgets/audit_screen.dart';
import '../widgets/recording_library_screen.dart';
import '../plugins/plugin_context_impl.dart';
import '../providers/plugin_engine_provider.dart';
import '../providers/plugin_provider.dart';
import '../services/ssh_service.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../models/shell_profile.dart';
import '../providers/settings_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../services/hotkey_service.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../widgets/script_plugin_panel_screen.dart';
import '../providers/share_provider.dart';
import '../widgets/join_share_dialog.dart';
import '../widgets/update_banner.dart';
import '../models/rdp_session.dart';
import '../widgets/rdp_workspace.dart';
import '../models/vnc_session.dart';
import '../widgets/vnc_workspace.dart';
import '../services/storage_service.dart';
import '../widgets/network_discovery_sheet.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

export 'shell/app_sidebar.dart' show NavSection;

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
  int _panelSerial = 0;
  String? _initialGroup;
  bool _viewingTerminal = false;
  bool _showAiChat = false;
  final _sftpConnectionNotifier = ValueNotifier<bool>(false);
  SessionProvider? _sessionProvider;
  KnownHostsProvider? _knownHostsProvider;
  SettingsProvider? _settingsProvider;
  TerminalLayoutProvider? _layoutProvider;
  bool _hostKeyDialogShowing = false;
  bool _rdpCertDialogShowing = false;
  bool _consentDialogShowing = false;
  bool _rdpFullscreen = false;
  bool _vncFullscreen = false;

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
    // Terminal-only features no-op on RDP tabs: their layout state is global
    // and persisted, so firing them against a remote-desktop tab would
    // corrupt the workspace snapshot restored on next launch.
    final isTerminal =
        context.read<SessionProvider>().activeSession is TerminalSession;
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
        if (isTerminal) {
          context.read<TerminalLayoutProvider>().toggleInputBar();
        }
      case 'split_horizontal':
        if (isTerminal) {
          context.read<TerminalLayoutProvider>().setLayout(SplitLayout.horizontal);
        }
      case 'split_vertical':
        if (isTerminal) {
          context.read<TerminalLayoutProvider>().setLayout(SplitLayout.vertical);
        }
      case 'command_palette':
        _openCommandPalette();
    }
  }

  // Fired by DualPanelSftpScreen's initState/dispose too (e.g. when RDP
  // fullscreen swaps the tree), i.e. while the framework is locked.
  void _onSftpConnectionChanged() => setStateSafely();

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
    // isResolved guard: a settled challenge can linger on the provider until
    // its awaiting caller resumes — never re-show a dialog for it.
    final challenge = _knownHostsProvider?.pendingChallenge;
    if (challenge != null &&
        !challenge.isResolved &&
        !_hostKeyDialogShowing &&
        mounted) {
      _hostKeyDialogShowing = true;
      showYsDialog<bool>(
        context,
        barrierDismissible: false,
        builder: (_) => HostKeyDialog(challenge: challenge),
      ).then((trusted) {
        challenge.resolve(trusted ?? false);
        _hostKeyDialogShowing = false;
        // A challenge raised while this dialog was open was skipped by the
        // guard above — re-check, or it would silently time out (2 min).
        scheduleMicrotask(_onKnownHostsChanged);
      });
    }

    final rdpChallenge = _knownHostsProvider?.pendingRdpChallenge;
    if (rdpChallenge != null &&
        !rdpChallenge.isResolved &&
        !_rdpCertDialogShowing &&
        mounted) {
      _rdpCertDialogShowing = true;
      showYsDialog<bool>(
        context,
        barrierDismissible: false,
        builder: (_) => RdpCertDialog(challenge: rdpChallenge),
      ).then((trusted) {
        rdpChallenge.resolve(trusted ?? false);
        _rdpCertDialogShowing = false;
        scheduleMicrotask(_onKnownHostsChanged);
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

  /// Host id a session restores from, or null for ephemeral tabs (local
  /// shells, watch sessions).
  static String? _restorableHostId(AppSession s) => switch (s) {
        SshSession ssh => ssh.isWatch ? null : ssh.host.id,
        RdpSession rdp => rdp.host.id,
        VncSession vnc => vnc.host.id,
        _ => null,
      };

  void _saveWorkspaceNow() {
    // SSH + RDP tabs — local sessions are ephemeral by design.
    final provider = _sessionProvider;
    final layout = _layoutProvider;
    if (provider == null || layout == null) return;
    final active = provider.activeSession;
    final snapshot = WorkspaceSnapshot(
      hostIds: provider.sessions
          .map(_restorableHostId)
          .whereType<String>()
          .toList(),
      activeHostId: active == null ? null : _restorableHostId(active),
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
      _panelSerial++;
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
      unawaited(sessionProvider.connectAny(host));
    }

    // Sessions are added synchronously at connect() entry; set active now.
    // (connectRdp has awaits before adding, so RDP tabs may land later —
    // the .last fallback in activeSession covers that gracefully.)
    if (snapshot.activeHostId != null) {
      final targetSession = sessionProvider.sessions
          .where((s) => _restorableHostId(s) == snapshot.activeHostId)
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
        icon: FLucideIcons.circlePlus,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openHostPanel()),
      ),
      CommandItem(
        id: 'action_import',
        title: 'Import SSH Config',
        subtitle: 'Import from ~/.ssh/config',
        icon: FLucideIcons.fileUp,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openImportPanel()),
      ),
      if (canShare)
        CommandItem(
          id: 'action_join_share',
          title: 'Join Shared Session',
          subtitle: 'Watch a colleague\'s terminal using a share code',
          icon: FLucideIcons.screenShare,
          type: CommandType.action,
          execute: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => showYsDialog(context, builder: (_) => const JoinShareDialog()),
          ),
        ),
      // Nav sections
      CommandItem(
        id: 'nav_hosts',
        title: 'Hosts',
        subtitle: 'Manage SSH connections',
        icon: FLucideIcons.server,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.hosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_sftp',
        title: 'SFTP',
        subtitle: 'File transfer',
        icon: FLucideIcons.folderOpen,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.sftp; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_keychain',
        title: 'Keychain',
        subtitle: 'SSH keys',
        icon: FLucideIcons.keyRound,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.keychain; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_port_forwarding',
        title: 'Port Forwarding',
        subtitle: 'Tunnel rules',
        icon: FLucideIcons.arrowLeftRight,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.portForwarding; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_local_terminal',
        title: 'Local Terminal',
        subtitle: 'Local shell',
        icon: FLucideIcons.laptop,
        type: CommandType.navSection,
        execute: _openLocalTerminal,
      ),
      CommandItem(
        id: 'nav_recordings',
        title: 'Recordings',
        subtitle: 'Session recordings',
        icon: FLucideIcons.clapperboard,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.recordings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_known_hosts',
        title: 'Known Hosts',
        subtitle: 'Host key verification',
        icon: FLucideIcons.listChecks,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.knownHosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_settings',
        title: 'Settings',
        subtitle: 'App preferences',
        icon: FLucideIcons.settings,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.settings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_plugins',
        title: 'Plugins',
        subtitle: 'Plugin marketplace',
        icon: FLucideIcons.puzzle,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.plugins; _viewingTerminal = false; }),
      ),
      // Hosts
      ...hosts.map((h) => CommandItem(
        id: 'host_${h.id}',
        title: h.label,
        subtitle: '${h.username}@${h.host}:${h.port}',
        icon: FLucideIcons.server,
        type: CommandType.host,
        execute: () async {
          setState(() => _viewingTerminal = true);
          await context.read<SessionProvider>().connectAny(h);
        },
      )),
    ];

    showYsDialog(context, builder: (_) => CommandPaletteDialog(items: items));
  }

  PluginContextImpl _pluginContext(String pluginId) {
    return _pluginContexts.putIfAbsent(pluginId, () => PluginContextImpl(
      sessions: context.read<SessionProvider>(),
      ssh: context.read<SshService>(),
      pluginId: pluginId,
    ));
  }

  /// Enters/exits RDP fullscreen: OS window fullscreen + the app chrome
  /// (tab bar, sidebar, panels) collapses to just the RdpWorkspace.
  Future<void> _setRdpFullscreen(bool on) async {
    if (_rdpFullscreen == on || !mounted) return;
    setState(() => _rdpFullscreen = on);
    try {
      await windowManager.setFullScreen(on);
    } catch (_) {
      // Window manager unavailable (tests/headless) — chrome state already
      // applied, which is the part that matters for correctness.
    }
  }

  /// Enters/exits VNC fullscreen: mirrors _setRdpFullscreen exactly.
  Future<void> _setVncFullscreen(bool on) async {
    if (_vncFullscreen == on || !mounted) return;
    setState(() => _vncFullscreen = on);
    try {
      await windowManager.setFullScreen(on);
    } catch (_) {
      // Window manager unavailable (tests/headless) — chrome state applied.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.watch<SessionProvider>();
    final sessions = sessionProvider.sessions;
    final activeSession = sessionProvider.activeSession;

    // Fullscreen only makes sense while an RDP tab is front-and-center;
    // anything that breaks that (tab switched via hotkey, tab closed, nav
    // changed) drops back to windowed mode instead of trapping the user in
    // a chrome-less screen.
    final rdpFullscreenActive =
        _rdpFullscreen && _viewingTerminal && activeSession is RdpSession;
    if (_rdpFullscreen && !rdpFullscreenActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_setRdpFullscreen(false));
      });
    }
    if (rdpFullscreenActive) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: _buildForeground(activeSession),
      );
    }

    final vncFullscreenActive =
        _vncFullscreen && _viewingTerminal && activeSession is VncSession;
    if (_vncFullscreen && !vncFullscreenActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_setVncFullscreen(false));
      });
    }
    if (vncFullscreenActive) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: _buildForeground(activeSession),
      );
    }

    final engineProvider = context.watch<PluginEngineProvider>();
    if (engineProvider.pendingConsent != null && !_consentDialogShowing) {
      _consentDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showYsDialog(
          context,
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
          SessionTabBar(
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
            onAddLocalSession: (
                {ShellProfile? profile, bool platformDefault = false}) {
              setState(() => _viewingTerminal = true);
              unawaited(context.read<SessionProvider>().newLocalSession(
                  profile: profile, platformDefault: platformDefault));
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
                  AppSidebar(
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
                      key: hostEditorKey(_editingHost, _panelSerial),
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
                      PluginStatusBarItem(item: item),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppSession? active) {
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

  Widget _buildForeground(AppSession? active) {
    if (_viewingTerminal && active is RdpSession) {
      return RdpWorkspace(
        session: active,
        onReconnect: () => _retryRdp(active),
        isFullscreen: _rdpFullscreen,
        onFullscreenChanged: (on) => unawaited(_setRdpFullscreen(on)),
      );
    }
    if (_viewingTerminal && active is VncSession) {
      return VncWorkspace(
        session: active,
        onReconnect: () => _retryVnc(active),
        isFullscreen: _vncFullscreen,
        onFullscreenChanged: (on) => unawaited(_setVncFullscreen(on)),
      );
    }
    if (_viewingTerminal && active != null) {
      // Hide the AI toggle (and any open chat panel) when no AI provider
      // has an API key configured — it appears once a key is saved.
      final aiConfigured = context.select<AiChatProvider, bool>(
          (p) => p.configuredProviders.isNotEmpty);
      final showAiChat = _showAiChat && aiConfigured;
      return Row(
        children: [
          Expanded(
            child: SplitTerminalView(
              onNavigateToSettings: () => setState(() {
                _nav = NavSection.settings;
                _viewingTerminal = false;
              }),
              // In the workspace header, not floated over it: a floating row
              // covered the header's right-aligned layout/panel buttons.
              toolbarTrailing: TerminalHeaderActions(
                active: active,
                aiConfigured: aiConfigured,
                aiOpen: showAiChat,
                onToggleAi: () => setState(() => _showAiChat = !_showAiChat),
              ),
            ),
          ),
          if (showAiChat)
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
          onDiscover: () => NetworkDiscoverySheet.show(context),
        ),
      NavSection.keychain => const KeychainScreen(),
      NavSection.portForwarding => const PortForwardingScreen(),
      // Rendered by the KeepAliveOffstage layer in _buildContent.
      NavSection.sftp => const SizedBox.shrink(),
      NavSection.recordings => const RecordingLibraryScreen(),
      NavSection.audit => const AuditScreen(),
      NavSection.knownHosts => const KnownHostsScreen(),
      NavSection.settings => const SettingsScreen(),
      NavSection.plugins => const PluginManagerScreen(),
    };
  }

  Future<void> _retryRdp(RdpSession old) async {
    final provider = context.read<SessionProvider>();
    if (old.status == RdpSessionStatus.error) {
      final newPassword = await showYsDialog<String>(
        context,
        builder: (_) => RdpPasswordDialog(host: old.host),
      );
      if (newPassword == null) return; // cancelled
      if (!mounted) return;
      await context.read<StorageService>().savePassword(old.host.id, newPassword);
    }
    if (!mounted) return;
    await provider.reconnectRdp(old);
  }

  Future<void> _retryVnc(VncSession old) async {
    if (!mounted) return;
    await context.read<SessionProvider>().reconnectVnc(old);
  }
}

// ── AI Chat Toggle Button ─────────────────────────────────

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
              const Icon(FLucideIcons.circleAlert, color: Colors.red, size: 32),
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
