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
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';

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

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _storage = StorageService();
    _ssh = SshService(_storage);
    _hostProvider = HostProvider(_storage);
    _keyProvider = KeyProvider();
    _settingsProvider = SettingsProvider();
    _sessionProvider = SessionProvider(_ssh);
    _sessionProvider.keyLookup = (id) => _keyProvider.findById(id);
    _sessionProvider.autoReconnectEnabled = () => _settingsProvider.autoReconnect;
    _sessionProvider.reconnectAttempts = () => _settingsProvider.reconnectAttempts;
    _sessionProvider.tmuxEnabled = () => _settingsProvider.tmuxEnabled;
    _knownHostsProvider = KnownHostsProvider(_storage);
    _knownHostsProvider.load();
    _sessionProvider.hostKeyVerifier = _knownHostsProvider.verifyHostKey;
    _sessionProvider.onOsDetected = (hostId, os) =>
        _hostProvider.updateDetectedOs(hostId, os);
    _pluginProvider = PluginProvider(plugins: kRegisteredPlugins);
    _pluginProvider.loadFromPrefs();
    // NOTE: onToggled lifecycle hooks (onActivate/onDeactivate) require a
    // YourSSHPluginContext, which needs SessionProvider from the widget tree.
    // Actual lifecycle wiring is done in MainScreen after the widget tree is built.
    _pluginProvider.onToggled = (plugin, enabled) {};
    _syncProvider = SyncProvider();
    _syncService = SyncService(_syncProvider);

    _hostProvider.onMutation = () => _syncService.push(
          hosts: _hostProvider.allHosts,
          loadPasswords: _loadAllPasswords,
        );

    _syncService.startRetryTimer(
      getHosts: () async => _hostProvider.allHosts,
      loadPasswords: _loadAllPasswords,
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

  Future<Map<String, String>> _loadAllPasswords() async {
    final passwords = <String, String>{};
    for (final host in _hostProvider.allHosts) {
      final pw = await _storage.loadPassword(host.id);
      if (pw != null) passwords['pw_${host.id}'] = pw;
    }
    return passwords;
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
    _syncService.dispose();
    _hostProvider.dispose();
    _keyProvider.dispose();
    _settingsProvider.dispose();
    _sessionProvider.dispose();
    _syncProvider.dispose();
    _knownHostsProvider.dispose();
    _pluginProvider.dispose();
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
