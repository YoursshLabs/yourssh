import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/host_provider.dart';
import 'providers/key_provider.dart';
import 'providers/port_forward_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/snippet_provider.dart';
import 'services/ssh_service.dart';
import 'services/storage_service.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YourSSHApp());
}

class YourSSHApp extends StatefulWidget {
  const YourSSHApp({super.key});

  @override
  State<YourSSHApp> createState() => _YourSSHAppState();
}

class _YourSSHAppState extends State<YourSSHApp> {
  late final StorageService _storage;
  late final SshService _ssh;
  late final HostProvider _hostProvider;
  late final KeyProvider _keyProvider;
  late final SettingsProvider _settingsProvider;
  late final SessionProvider _sessionProvider;

  @override
  void initState() {
    super.initState();
    _storage = StorageService();
    _ssh = SshService(_storage);
    _hostProvider = HostProvider(_storage);
    _keyProvider = KeyProvider();
    _settingsProvider = SettingsProvider();
    _sessionProvider = SessionProvider(_ssh);
    _sessionProvider.keyLookup = (id) => _keyProvider.findById(id);
    _sessionProvider.autoReconnectEnabled = () => _settingsProvider.autoReconnect;
    _sessionProvider.reconnectAttempts = () => _settingsProvider.reconnectAttempts;
  }

  @override
  void dispose() {
    _hostProvider.dispose();
    _keyProvider.dispose();
    _settingsProvider.dispose();
    _sessionProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _ssh),
        ChangeNotifierProvider.value(value: _hostProvider),
        ChangeNotifierProvider.value(value: _keyProvider),
        ChangeNotifierProvider.value(value: _settingsProvider),
        ChangeNotifierProvider.value(value: _sessionProvider),
        ChangeNotifierProvider(create: (_) => PortForwardProvider()),
        ChangeNotifierProvider(create: (_) => SnippetProvider()),
      ],
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
      ),
    );
  }
}
