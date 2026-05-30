import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/ai_chat_provider.dart';
import 'providers/command_history_provider.dart';
import 'providers/host_provider.dart';
import 'providers/key_provider.dart';
import 'providers/port_forward_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'providers/local_session_provider.dart';
import 'providers/terminal_layout_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/known_hosts_provider.dart';
import 'providers/plugin_provider.dart';
import 'plugins/plugin_registry.dart';
import 'services/notification_service.dart';
import 'services/ssh_service.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/recording_service.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';
import 'providers/recording_provider.dart';

String kAppVersion = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kAppVersion = (await PackageInfo.fromPlatform()).version;
  await windowManager.ensureInitialized();
  await windowManager.setTitle('YourSSH');
  await windowManager.setMinimumSize(const Size(800, 600));
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
  late final SyncProvider _syncProvider;
  late final SyncService _syncService;
  late final KnownHostsProvider _knownHostsProvider;
  late final PluginProvider _pluginProvider;
  late final RecordingService _recordingService;
  late final RecordingProvider _recordingProvider;

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _storage = StorageService();
    _recordingService = RecordingService();
    _recordingProvider = RecordingProvider(
      _recordingService,
      getPath: () => _settingsProvider.recordingPath,
    );
    _ssh = SshService(_storage);
    _ssh.recordingService = _recordingService;
    _hostProvider = HostProvider(_storage);
    _keyProvider = KeyProvider();
    _settingsProvider = SettingsProvider();
    _sessionProvider = SessionProvider(_ssh);
    _sessionProvider.keyLookup = (id) => _keyProvider.findById(id);
    _sessionProvider.jumpHostLookup = (id) =>
        _hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
    _sessionProvider.autoReconnectEnabled = () => _settingsProvider.autoReconnect;
    _sessionProvider.reconnectAttempts = () => _settingsProvider.reconnectAttempts;
    _sessionProvider.tmuxEnabled = () => _settingsProvider.tmuxEnabled;
    _sessionProvider.recordingStart = (s) => _recordingProvider.startRecording(s);
    _knownHostsProvider = KnownHostsProvider(_storage);
    _knownHostsProvider.load();
    _sessionProvider.hostKeyVerifier = _knownHostsProvider.verifyHostKey;
    _ssh.defaultHostKeyVerifier = _knownHostsProvider.verifyHostKey;
    _sessionProvider.onOsDetected = (hostId, os) =>
        _hostProvider.updateDetectedOs(hostId, os);
    _pluginProvider = PluginProvider(plugins: kRegisteredPlugins);
    _pluginProvider.loadFromPrefs();
    // NOTE: onToggled lifecycle hooks (onActivate/onDeactivate) require a
    // YourSSHPluginContext, which needs SessionProvider from the widget tree.
    // Actual lifecycle wiring is done in MainScreen after the widget tree is built.
    _pluginProvider.onToggled = (plugin, enabled) {};
    _syncProvider = SyncProvider(storage: _storage);
    _syncService = SyncService(_syncProvider);

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
    _pluginProvider.dispose();
    _recordingProvider.dispose();
    _sessionProvider.dispose();
    _syncService.dispose();
    _syncProvider.dispose();
    _knownHostsProvider.dispose();
    _hostProvider.dispose();
    _keyProvider.dispose();
    _settingsProvider.dispose();
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
        ChangeNotifierProvider.value(value: _knownHostsProvider),
        ChangeNotifierProvider.value(value: _syncProvider),
        Provider.value(value: _syncService),
        ChangeNotifierProvider(create: (_) => PortForwardProvider()),
        ChangeNotifierProvider(create: (_) => SnippetProvider()),
        ChangeNotifierProvider(create: (_) {
          final p = CommandHistoryProvider();
          p.init();
          return p;
        }),
        ChangeNotifierProvider(create: (_) => TerminalLayoutProvider()),
        ChangeNotifierProvider(create: (_) => LocalSessionProvider()),
        ChangeNotifierProvider(create: (_) => AiChatProvider()),
        ChangeNotifierProvider.value(value: _pluginProvider),
        ChangeNotifierProvider.value(value: _recordingProvider),
      ],
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
      ),
    );
  }
}
