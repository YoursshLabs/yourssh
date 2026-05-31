import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../js_runtime_registrar.dart';
import 'quickjs_ffi.dart' as ffi;

// ---------------------------------------------------------------------------
// Exception type
// ---------------------------------------------------------------------------

class QuickJsException implements Exception {
  final String message;
  const QuickJsException(this.message);
  @override
  String toString() => 'QuickJsException: $message';
}

// ---------------------------------------------------------------------------
// Native callback typedef — matches QjsHostCallback in qjs_bridge.h:
//   char* callback(const char* arg_json, void* user_data)
// ---------------------------------------------------------------------------

typedef _QjsHostCbNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Void>);

// ---------------------------------------------------------------------------
// qjs_register_host_fn binding (done lazily here because it needs the
// NativeFunction type that references _QjsHostCbNative)
// ---------------------------------------------------------------------------

typedef _RegisterHostFnNative = Void Function(
    ffi.QjsContextPtr,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<NativeFunction<_QjsHostCbNative>>,
    Pointer<Void>);

typedef _RegisterHostFnDart = void Function(
    ffi.QjsContextPtr,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<NativeFunction<_QjsHostCbNative>>,
    Pointer<Void>);

// ---------------------------------------------------------------------------
// QuickJsRuntime
// ---------------------------------------------------------------------------

/// A high-level wrapper around one QuickJS context.
///
/// Implements [JsRuntimeRegistrar] so bridge classes (StorageBridge, SshBridge,
/// SftpBridge, UiBridge) can register host-callable functions without coupling
/// to the FFI details.
class QuickJsRuntime implements JsRuntimeRegistrar {
  final ffi.QjsContextPtr _ctx;
  bool _disposed = false;

  /// Keeps [NativeCallable] instances alive for the lifetime of the runtime so
  /// the C side can invoke the callbacks at any time.
  final _callables = <NativeCallable<_QjsHostCbNative>>[];

  // Lazily resolved binding for qjs_register_host_fn.
  static _RegisterHostFnDart? _registerHostFnBinding;

  static _RegisterHostFnDart _getRegisterHostFn() {
    return _registerHostFnBinding ??=
        ffi.lib.lookupFunction<_RegisterHostFnNative, _RegisterHostFnDart>(
            'qjs_register_host_fn');
  }

  QuickJsRuntime() : _ctx = ffi.qjsContextNew();

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Evaluate [source] in the QuickJS context.
  ///
  /// [filename] is used only for error messages.
  /// Throws [QuickJsException] if the script throws or contains a syntax error.
  void eval(String source, {required String filename}) {
    _checkNotDisposed();
    final src = source.toNativeUtf8();
    final file = filename.toNativeUtf8();
    try {
      final ok = ffi.qjsEval(_ctx, src, file);
      if (ok == 0) {
        final errPtr = ffi.qjsGetException(_ctx);
        final msg = errPtr.toDartString();
        ffi.qjsStringFree(errPtr);
        throw QuickJsException(msg);
      }
    } finally {
      malloc.free(src);
      malloc.free(file);
    }
  }

  /// Register a Dart function as `bridgeName.fnName(jsonArg)` in JS.
  ///
  /// [handler] receives the JSON-encoded argument string and should return a
  /// JSON-encoded result string, or `null` for void calls.
  ///
  /// Implements [JsRuntimeRegistrar].
  @override
  void registerHostFn(
    String bridgeName,
    String fnName,
    String? Function(String arg) handler,
  ) {
    _checkNotDisposed();

    // NativeCallable.isolateLocal is called synchronously on the current Dart
    // isolate — safe here because QuickJS is single-threaded and eval() is
    // synchronous, so the callback is always invoked from the same isolate that
    // called eval().
    final callable = NativeCallable<_QjsHostCbNative>.isolateLocal(
      (Pointer<Utf8> argPtr, Pointer<Void> _) {
        try {
          final arg = argPtr.address != 0 ? argPtr.toDartString() : 'null';
          final result = handler(arg);
          if (result == null) return Pointer<Utf8>.fromAddress(0);
          // Allocate with malloc. The C bridge copies the string immediately
          // into a JS value and does NOT call qjs_string_free on this pointer,
          // so this is a one-per-call allocation.  Acceptable because the
          // strings are small and the C side copies immediately.
          return result.toNativeUtf8(allocator: malloc);
        } catch (_) {
          return Pointer<Utf8>.fromAddress(0);
        }
      },
    );

    _callables.add(callable);

    final bridge = bridgeName.toNativeUtf8();
    final fn = fnName.toNativeUtf8();
    try {
      _getRegisterHostFn()(
          _ctx, bridge, fn, callable.nativeFunction, nullptr);
    } finally {
      malloc.free(bridge);
      malloc.free(fn);
    }
  }

  /// Call `plugin._dispatch(event, ctxJson)` in the JS runtime and return the
  /// JSON-encoded result, or `null` if dispatch fails or returns undefined.
  String? callDispatch(String event, Map<String, dynamic> ctx) {
    _checkNotDisposed();
    final arg = json.encode(ctx);

    // Step 1: call dispatch and store in a global.
    final dispatchJs =
        'var __qjsBridgeResult = plugin._dispatch(${json.encode(event)}, ${json.encode(arg)});';
    try {
      eval(dispatchJs, filename: '<dispatch>');
    } catch (_) {
      return null;
    }

    // Step 2: define a getter function (idempotent — redefining is harmless).
    try {
      eval(
        'function __getResult() { return JSON.stringify(__qjsBridgeResult); }',
        filename: '<dispatch-getter>',
      );
    } catch (_) {}

    // Step 3: invoke the getter via qjs_call_fn.
    final fnName = '__getResult'.toNativeUtf8();
    final argStr = 'null'.toNativeUtf8();
    try {
      final resultPtr = ffi.qjsCallFn(_ctx, fnName, argStr);
      if (resultPtr.address == 0) return null;
      final result = resultPtr.toDartString();
      ffi.qjsStringFree(resultPtr);
      return result;
    } finally {
      malloc.free(fnName);
      malloc.free(argStr);
    }
  }

  /// Call `plugin._invokePanelMessage(msgJson)` in the JS runtime.
  ///
  /// Returns the JSON-encoded result string from the plugin's panel message
  /// handler, or `null` if no handler is set or an error occurs.
  String? callPanelMessage(Map<String, dynamic> msg) {
    _checkNotDisposed();
    final msgJson = json.encode(msg);

    // Store result in a global via eval.
    final invokeJs =
        'var __qjsPanelResult = plugin._invokePanelMessage(${json.encode(msgJson)});';
    try {
      eval(invokeJs, filename: '<panel-message>');
    } catch (_) {
      return null;
    }

    // Define getter (idempotent).
    try {
      eval(
        'function __getPanelResult() { return __qjsPanelResult; }',
        filename: '<panel-message-getter>',
      );
    } catch (_) {}

    // Read result via qjs_call_fn.
    final fnName = '__getPanelResult'.toNativeUtf8();
    final argStr = 'null'.toNativeUtf8();
    try {
      final resultPtr = ffi.qjsCallFn(_ctx, fnName, argStr);
      if (resultPtr.address == 0) return null;
      final result = resultPtr.toDartString();
      ffi.qjsStringFree(resultPtr);
      return result == 'null' ? null : result;
    } finally {
      malloc.free(fnName);
      malloc.free(argStr);
    }
  }

  /// Release the QuickJS context and all registered callbacks.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final c in _callables) {
      c.close();
    }
    _callables.clear();
    ffi.qjsContextFree(_ctx);
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  void _checkNotDisposed() {
    if (_disposed) throw StateError('QuickJsRuntime already disposed');
  }
}
