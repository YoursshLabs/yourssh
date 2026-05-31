import 'dart:convert';
import '../permission_guard.dart';
import '../js_runtime_registrar.dart';

abstract class SshBridgeDelegate {
  List<Map<String, dynamic>> activeSessions();
  Future<Map<String, dynamic>> execCommand(String sessionId, String command);
  void sendInput(String sessionId, String text);
}

class SshBridge {
  final PermissionGuard _guard;
  final SshBridgeDelegate _delegate;

  SshBridge(this._guard, this._delegate);

  void register(JsRuntimeRegistrar rt) {
    if (_guard.has('session.observe') || _guard.has('ssh.exec')) {
      rt.registerHostFn('_ssh', 'sessions', _sessions);
    }
    if (_guard.has('ssh.exec')) {
      rt.registerHostFn('_ssh', 'exec', _execStub);
    }
  }

  String? _sessions(String _) => json.encode(_delegate.activeSessions());

  // Async bridge wired in ScriptEngineService — sync stub here prevents crashes
  String? _execStub(String _) => json.encode({'error': 'Use async bridge'});
}
