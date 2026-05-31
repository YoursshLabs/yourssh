import 'dart:convert';
import '../permission_guard.dart';
import '../js_runtime_registrar.dart';

abstract class TerminalInjectDelegate {
  void sendInput(String sessionId, String text);
}

class TerminalInjectBridge {
  final PermissionGuard _guard;
  final TerminalInjectDelegate _delegate;

  TerminalInjectBridge(this._guard, this._delegate);

  void register(JsRuntimeRegistrar rt) {
    if (!_guard.has('terminal.inject')) return;
    rt.registerHostFn('_ssh', 'inject', _inject);
  }

  String? _inject(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final sessionId = arg['sessionId'] as String;
    final text = arg['text'] as String;
    _delegate.sendInput(sessionId, text);
    return null;
  }
}
