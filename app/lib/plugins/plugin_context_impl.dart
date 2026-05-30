import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../models/ssh_session.dart';
import '../providers/session_provider.dart';
import '../services/ssh_service.dart';

class PluginContextImpl implements YourSSHPluginContext {
  final SessionProvider _sessions;
  // ignore: unused_field
  final SshService _ssh;
  final String _pluginId;

  PluginContextImpl({
    required this._sessions,
    required this._ssh,
    required this._pluginId,
  });

  @override
  List<SSHSessionProxy> get activeSessions => _sessions.sessions
      .map((s) => SSHSessionProxy(
            sessionId: s.id,
            hostLabel: '${s.host.username}@${s.host.host}',
            isConnected: s.status == SessionStatus.connected,
          ))
      .toList();

  /// NOTE: SshService.exec() requires a Host object, not a session ID.
  /// A future implementation should maintain a sessionId→Host mapping in
  /// SshService. For now this throws PluginSSHException('not implemented').
  @override
  Future<String> execCommand(String sessionId, String command) async {
    throw const PluginSSHException(
      'execCommand not implemented: SshService.exec() requires a Host object. '
      'Add execBySessionId(sessionId, command) to SshService in a follow-up task.',
    );
  }

  @override
  Future<void> savePreference(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin::$_pluginId::$key', value);
  }

  @override
  Future<String?> getPreference(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('plugin::$_pluginId::$key');
  }
}
