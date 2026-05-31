import '../permission_guard.dart';

abstract class SftpBridgeDelegate {
  Future<List<Map<String, dynamic>>> listDir(String sessionId, String path);
  Future<String> readFile(String sessionId, String path);
  Future<void> writeFile(String sessionId, String path, String content);
  Future<void> deleteFile(String sessionId, String path);
  Future<void> makeDir(String sessionId, String path);
}

// TODO: remove when QuickJsRuntime implements JsRuntimeRegistrar
abstract class JsRuntimeRegistrar {
  void registerHostFn(
      String bridgeName, String fnName, String? Function(String arg) handler);
}

class SftpBridge {
  final PermissionGuard _guard;
  final SftpBridgeDelegate _delegate;

  SftpBridge(this._guard, this._delegate);

  void register(JsRuntimeRegistrar rt) {
    if (_guard.has('sftp.read')) {
      rt.registerHostFn('_sftp', 'list', (_) => null);
      rt.registerHostFn('_sftp', 'read', (_) => null);
    }
    if (_guard.has('sftp.write')) {
      rt.registerHostFn('_sftp', 'write', (_) => null);
      rt.registerHostFn('_sftp', 'delete', (_) => null);
      rt.registerHostFn('_sftp', 'mkdir', (_) => null);
    }
  }

  SftpBridgeDelegate get delegate => _delegate;
}
