import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'utils/bundled_plugin_installer.dart';
import 'providers/ai_chat_provider.dart';
import 'providers/command_history_provider.dart';
import 'providers/host_provider.dart';
import 'providers/key_provider.dart';
import 'providers/plugin_engine_provider.dart';
import 'providers/port_forward_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/shell_integration_provider.dart';
import 'providers/terminal_layout_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/known_hosts_provider.dart';
import 'providers/plugin_provider.dart';
import 'plugins/plugin_registry.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'services/health_monitor_service.dart';
import 'services/local_shell_service.dart';
import 'services/notification_service.dart';
import 'services/ssh_service.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/recording_service.dart';
import 'services/tab_metadata_service.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/sudo_password_dialog.dart';
import 'providers/recording_provider.dart';
import 'providers/share_provider.dart';
import 'services/update_service.dart';
import 'providers/update_provider.dart';

String kAppVersion = '';

/// Lazy adapter so ScriptEngineService can call into SessionProvider / SshService
/// without a circular initialization dependency.
class _SshBridgeAdapter implements SshBridgeDelegate {
  final SessionProvider Function() _getSessionProvider;
  final SshService Function() _getSshService;

  _SshBridgeAdapter(this._getSessionProvider, this._getSshService);

  @override
  List<Map<String, dynamic>> activeSessions() {
    return _getSessionProvider().sshSessions.map((s) => {
          'sessionId': s.id,
          'host': s.host.host,
          'username': s.host.username,
          'port': s.host.port,
          'connected': s.status.name == 'connected',
        }).toList();
  }

  @override
  Future<Map<String, dynamic>> execCommand(
      String sessionId, String command) async {
    final session = _getSessionProvider()
        .sshSessions
        .firstWhere((s) => s.id == sessionId);
    final result = await _getSshService().exec(session.host, command);
    return {
      'stdout': result.stdout,
      'stderr': result.stderr,
      'exitCode': result.exitCode,
    };
  }

  @override
  void sendInput(String sessionId, String text) =>
      _getSshService().sendInput(sessionId, text);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kAppVersion = (await PackageInfo.fromPlatform()).version;
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    title: 'YourSSH',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await hotKeyManager.unregisterAll();
  await NotificationService.init();
  runApp(const YourSSHApp());
}

class YourSSHApp extends StatefulWidget {
  const YourSSHApp({super.key});

  @override
  State<YourSSHApp> createState() => _YourSSHAppState();
}

class _YourSSHAppState extends State<YourSSHApp> with WindowListener {
  late final StorageService _storage;
  late final SshService _ssh;
  late final HostProvider _hostProvider;
  late final KeyProvider _keyProvider;
  late final SettingsProvider _settingsProvider;
  late final SessionProvider _sessionProvider;
  late final LocalShellService _localShell;
  late final SyncProvider _syncProvider;
  late final SyncService _syncService;
  late final KnownHostsProvider _knownHostsProvider;
  late final PluginProvider _pluginProvider;
  late final RecordingService _recordingService;
  late final RecordingProvider _recordingProvider;
  late final HookBus _hookBus;
  late final PluginUiRegistry _uiRegistry;
  late final PluginEngineProvider _pluginEngineProvider;
  late final ShareProvider _shareProvider;
  late final HealthMonitorService _healthMonitor;
  late final ShellIntegrationProvider _shellIntegrationProvider;
  late final UpdateService _updateService;
  late final UpdateProvider _updateProvider;

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _storage = StorageService();
    _recordingService = RecordingService();
    _localShell = LocalShellService();
    _localShell.recordingService = _recordingService;
    _recordingProvider = RecordingProvider(
      _recordingService,
      getPath: () => _settingsProvider.recordingPath,
    );
    _hookBus = HookBus();
    _uiRegistry = PluginUiRegistry();
    _shellIntegrationProvider = ShellIntegrationProvider();
    _ssh = SshService(_storage,
        hookBus: _hookBus, shellIntegration: _shellIntegrationProvider);
    _ssh.recordingService = _recordingService;
    _hostProvider = HostProvider(_storage);
    _keyProvider = KeyProvider();
    _settingsProvider = SettingsProvider();
    _ssh.isShellIntegrationEnabled =
        () => _settingsProvider.shellIntegrationEnabled;
    _sessionProvider = SessionProvider(_ssh, TabMetadataService());
    _sessionProvider.localShell = _localShell;
    _sessionProvider.keyLookup = (id) => _keyProvider.findById(id);
    _sessionProvider.jumpHostLookup = (id) =>
        _hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
    _sessionProvider.autoReconnectEnabled = () => _settingsProvider.autoReconnect;
    _sessionProvider.reconnectAttempts = () => _settingsProvider.reconnectAttempts;
    _sessionProvider.tmuxEnabled = () => _settingsProvider.tmuxEnabled;
    _sessionProvider.recordingStart = (s) => _recordingProvider.startRecording(s);
    _healthMonitor = HealthMonitorService(
      measure: _ssh.measureLatency,
      connectedHostIds: () => _ssh.connectedHostIds,
      pollSeconds: () => _settingsProvider.keepAliveInterval,
    )..start();
    _knownHostsProvider = KnownHostsProvider(_storage);
    _knownHostsProvider.load();
    _sessionProvider.hostKeyVerifier = _knownHostsProvider.verifyHostKey;
    _ssh.defaultHostKeyVerifier = _knownHostsProvider.verifyHostKey;
    // Returns (password, remember); SshService persists it only after it
    // validates, so a wrong "remembered" password is never stored.
    _ssh.sudoPasswordPrompt = (host) async {
      final ctx = _navigatorKey.currentContext;
      if (ctx == null) return null;
      return showDialog<({String password, bool remember})>(
        context: ctx,
        builder: (_) => SudoPasswordDialog(host: host),
      );
    };
    _sessionProvider.onOsDetected = (hostId, os) =>
        _hostProvider.updateDetectedOs(hostId, os);
    _pluginProvider = PluginProvider(plugins: kRegisteredPlugins);
    _pluginProvider.loadFromPrefs();
    // NOTE: onToggled lifecycle hooks (onActivate/onDeactivate) require a
    // YourSSHPluginContext, which needs SessionProvider from the widget tree.
    // Actual lifecycle wiring is done in MainScreen after the widget tree is built.
    _pluginProvider.onToggled = (plugin, enabled) {};

    // Wire ScriptEngineService with a lazy SSH bridge adapter.
    // The adapter captures _sessionProvider and _ssh by reference; they are
    // already assigned above so any plugin call at runtime is safe.
    final sshAdapter = _SshBridgeAdapter(
      () => _sessionProvider,
      () => _ssh,
    );
    final engine = ScriptEngineService(
      hookBus: _hookBus,
      uiRegistry: _uiRegistry,
      sshDelegate: sshAdapter,
      sftpDelegate: null,
      onLog: (pluginId, level, message) {
        _pluginEngineProvider.addLog(pluginId, '[$level] $message');
      },
    );
    // PluginEngineProvider must be created before PluginLoader because the
    // loader's onConsentRequired callback closes over _pluginEngineProvider.
    // Use a late local var pattern: assign _pluginEngineProvider after loader.
    late final PluginLoader loader;
    loader = PluginLoader(
      engine: engine,
      onConsentRequired: (id, manifest, dir) {
        _pluginEngineProvider.setPendingConsent(id, manifest, dir);
      },
      onError: (id, msg) {
        _pluginEngineProvider.addLog(id, '[ERROR] $msg');
      },
    );
    _pluginEngineProvider = PluginEngineProvider(
      engine: engine,
      loader: loader,
      hookBus: _hookBus,
      uiRegistry: _uiRegistry,
    );
    // Install bundled plugins, warm up migration cache, then scan for plugins.
    // Runs async so initState() stays synchronous.
    Future(() async {
      await BundledPluginInstaller.ensureInstalled('snippets');
      await MigrationBridge.warmup();
      loader.scanAndLoad();
    });

    _syncProvider = SyncProvider(storage: _storage);
    _syncService = SyncService(_syncProvider);
    _shareProvider = ShareProvider(syncProvider: _syncProvider);
    _updateService = UpdateService();
    _updateProvider = UpdateProvider(_updateService, currentVersion: kAppVersion);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateProvider.checkForUpdates();
    });
    _shareProvider.wireDependencies(_sessionProvider, _hookBus);
    _shareProvider.onGuestInput = (data) {
      final sessionId = _shareProvider.sharingSessionId;
      if (sessionId == null) return;
      final session = _sessionProvider.sshSessions
          .where((s) => s.id == sessionId && !s.isWatch)
          .firstOrNull;
      session?.terminal.textInput(data);
    };

    _hostProvider.onMutation = () => _syncService.push(
          hosts: _hostProvider.allHosts,
          loadPasswords: _hostProvider.loadAllPasswords,
        );

    _syncService.startRetryTimer(
      getHosts: () async => _hostProvider.allHosts,
      loadPasswords: _hostProvider.loadAllPasswords,
    );

    NotificationService.instance.enabled = _settingsProvider.commandNotificationsEnabled;
    _settingsProvider.addListener(_syncNotificationSetting);
    NotificationService.instance.onToast = (label) {
      _messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('✓ $label — command finished'),
        duration: const Duration(seconds: 3),
      ));
    };
  }

  void _syncNotificationSetting() {
    NotificationService.instance.enabled = _settingsProvider.commandNotificationsEnabled;
  }

  @override
  void onWindowFocus() {
    NotificationService.instance.onWindowFocus();
    if (_syncProvider.enabled) {
      _syncService.pull().then((payload) {
        if (payload != null) {
          _hostProvider.replaceAll(payload.hosts, payload.passwords);
        }
      });
    }
  }

  @override
  void onWindowBlur() {
    NotificationService.instance.onWindowBlur();
  }

  @override
  void dispose() {
    _settingsProvider.removeListener(_syncNotificationSetting);
    windowManager.removeListener(this);
    // Tear down in reverse-dependency order: consumers first (sessions, plugins,
    // recording, sync service — they read host/key/settings via callbacks), then
    // the producers they depend on.
    _pluginEngineProvider.dispose();
    _pluginProvider.dispose();
    _recordingProvider.dispose();
    _healthMonitor.dispose();
    _sessionProvider.dispose();
    _syncService.dispose();
    _syncProvider.dispose();
    _knownHostsProvider.dispose();
    _hostProvider.dispose();
    _keyProvider.dispose();
    _settingsProvider.dispose();
    _shellIntegrationProvider.dispose();
    _updateProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _storage),
        Provider.value(value: _ssh),
        ChangeNotifierProvider.value(value: _hostProvider),
        ChangeNotifierProvider.value(value: _keyProvider),
        ChangeNotifierProvider.value(value: _settingsProvider),
        ChangeNotifierProvider.value(value: _sessionProvider),
        ChangeNotifierProvider.value(value: _healthMonitor),
        ChangeNotifierProvider.value(value: _shellIntegrationProvider),
        ChangeNotifierProvider.value(value: _knownHostsProvider),
        ChangeNotifierProvider.value(value: _syncProvider),
        ChangeNotifierProvider.value(value: _shareProvider),
        Provider.value(value: _syncService),
        ChangeNotifierProvider(create: (_) => PortForwardProvider()),
        ChangeNotifierProvider(create: (_) {
          final p = CommandHistoryProvider();
          p.init();
          return p;
        }),
        ChangeNotifierProvider(create: (_) => TerminalLayoutProvider()),
        ChangeNotifierProvider(create: (_) => AiChatProvider()),
        ChangeNotifierProvider(create: (_) => SnippetProvider()),
        ChangeNotifierProvider.value(value: _pluginProvider),
        ChangeNotifierProvider.value(value: _recordingProvider),
        ChangeNotifierProvider.value(value: _uiRegistry),
        ChangeNotifierProvider.value(value: _pluginEngineProvider),
        ChangeNotifierProvider.value(value: _updateProvider),
      ],
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        navigatorKey: _navigatorKey,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
      ),
    );
  }
}
