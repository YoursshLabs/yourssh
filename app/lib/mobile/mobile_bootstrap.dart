import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../providers/known_hosts_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/tab_metadata_service.dart';

/// Constructs the platform-agnostic services/providers the Android app needs
/// and wires the minimal callbacks required to connect over SSH. Mirrors the
/// desktop wiring in `main.dart` but only for the mobile-relevant subset —
/// kept separate so the desktop bootstrap stays untouched.
class MobileBootstrap {
  late final StorageService storage;
  late final SshService ssh;
  late final HostProvider hostProvider;
  late final KeyProvider keyProvider;
  late final SettingsProvider settings;
  late final KnownHostsProvider knownHosts;
  late final SessionProvider sessions;
  late final SyncProvider sync;
  late final SyncService syncService;
  late final SnippetProvider snippets;
  late final SftpTransferService transfer;

  MobileBootstrap() {
    storage = StorageService();
    ssh = SshService(storage);
    hostProvider = HostProvider(storage);
    keyProvider = KeyProvider()..savePassphrase = storage.savePassphrase;
    settings = SettingsProvider();
    knownHosts = KnownHostsProvider(storage)..load();
    sessions = SessionProvider(ssh, TabMetadataService());
    sync = SyncProvider(storage: storage);
    syncService = SyncService(sync);
    snippets = SnippetProvider();
    transfer = SftpTransferService(ssh);
    _wire();
  }

  void _wire() {
    sessions.keyLookup = (id) => keyProvider.findById(id);
    sessions.jumpHostLookup =
        (id) => hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
    sessions.autoReconnectEnabled = () => settings.autoReconnect;
    sessions.reconnectAttempts = () => settings.reconnectAttempts;
    sessions.tmuxEnabled = () => settings.tmuxEnabled;
    sessions.terminalType = () => settings.terminalType;
    sessions.hostKeyVerifier = knownHosts.verifyHostKey;
    sessions.onOsDetected = (id, os) => hostProvider.updateDetectedOs(id, os);

    ssh.defaultHostKeyVerifier = knownHosts.verifyHostKey;
    ssh.defaultKeyLookup = (id) => keyProvider.findById(id);
    ssh.defaultJumpHostLookup =
        (id) => hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
  }

  List<SingleChildWidget> get providers => [
        Provider.value(value: storage),
        Provider.value(value: ssh),
        ChangeNotifierProvider.value(value: hostProvider),
        ChangeNotifierProvider.value(value: keyProvider),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: knownHosts),
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: sync),
        Provider.value(value: syncService),
        ChangeNotifierProvider.value(value: snippets),
        Provider.value(value: transfer),
      ];

  /// Disposes the objects exposed via `Provider.value` (which does not dispose
  /// them itself), most importantly [SessionProvider]'s reconnect timers and
  /// [SyncService]'s retry timer. Called from the root widget's dispose.
  void dispose() {
    syncService.dispose();
    sessions.dispose();
    sync.dispose();
    snippets.dispose();
    knownHosts.dispose();
    settings.dispose();
    keyProvider.dispose();
    hostProvider.dispose();
  }
}
