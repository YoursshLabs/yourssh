import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../models/ssh_session.dart';
import '../providers/session_provider.dart';
import '../services/ssh_service.dart';

/// Plugin IDs must match this pattern so the preference namespace
/// `plugin::<id>::<key>` can't be ambiguously parsed — e.g., an id of
/// `foo::bar` would collide with plugin `foo` storing key `bar::…`.
final RegExp kValidPluginId = RegExp(r'^[a-z0-9][a-z0-9._\-]{0,63}$');

class PluginContextImpl implements YourSSHPluginContext {
  final SessionProvider _sessions;
  final SshService _ssh;
  final String _pluginId;

  PluginContextImpl({
    required SessionProvider sessions,
    required SshService ssh,
    required String pluginId,
    // ignore: prefer_initializing_formals
  })  : _sessions = sessions,
        // ignore: prefer_initializing_formals
        _ssh = ssh,
        _pluginId = pluginId {
    if (!kValidPluginId.hasMatch(pluginId)) {
      throw ArgumentError.value(
        pluginId,
        'pluginId',
        'must match ${kValidPluginId.pattern}',
      );
    }
  }

  SSHSessionProxy _toProxy(SshSession s, {required bool isActive}) =>
      SSHSessionProxy(
        sessionId: s.id,
        hostLabel: '${s.host.username}@${s.host.host}',
        isConnected: s.status == SessionStatus.connected,
        isActive: isActive,
      );

  @override
  List<SSHSessionProxy> get activeSessions => _sessions.sshSessions
      .map((s) => _toProxy(s, isActive: _sessions.activeSession?.id == s.id))
      .toList();

  @override
  SSHSessionProxy? get activeSession {
    final session = _sessions.activeSshSession;
    if (session == null) return null;
    return _toProxy(session, isActive: true);
  }

  @override
  Future<String> execCommand(String sessionId, String command) async {
    final host = _sessions.hostForSession(sessionId);
    if (host == null) {
      throw PluginSSHException('Unknown session: $sessionId');
    }
    final result = await _ssh.exec(host, command);
    if (result.exitCode != 0) {
      throw PluginSSHException(
        'Command exited ${result.exitCode}: ${result.stderr.trim()}',
      );
    }
    return result.stdout;
  }

  @override
  Future<void> sendInput(String sessionId, String text) async {
    final session =
        _sessions.sshSessions.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) {
      throw PluginSSHException('Unknown session: $sessionId');
    }
    if (session.status != SessionStatus.connected) {
      throw PluginSSHException('Session is not connected: $sessionId');
    }

    if (!_ssh.sendInput(sessionId, text)) {
      throw PluginSSHException('Session has no open shell: $sessionId');
    }
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
