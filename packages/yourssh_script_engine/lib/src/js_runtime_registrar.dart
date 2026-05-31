/// Minimal interface a JS runtime must expose so bridge classes can register
/// host-side functions callable from JavaScript.
abstract class JsRuntimeRegistrar {
  void registerHostFn(
    String bridgeName,
    String fnName,
    String? Function(String arg) handler,
  );
}
