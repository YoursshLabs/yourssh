import 'ssh_session_proxy.dart';

abstract class YourSSHPluginContext {
  List<SSHSessionProxy> get activeSessions;
  SSHSessionProxy? get activeSession;

  /// Runs [command] on the given session. Throws [PluginSSHException] on failure.
  Future<String> execCommand(String sessionId, String command);

  /// Sends raw [text] to the live terminal of the given session.
  Future<void> sendInput(String sessionId, String text);

  /// Preferences are auto-namespaced by plugin ID.
  Future<void> savePreference(String key, String value);
  Future<String?> getPreference(String key);
}
