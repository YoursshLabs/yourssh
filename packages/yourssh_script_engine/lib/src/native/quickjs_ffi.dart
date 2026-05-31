import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Loads the QuickJS bridge shared library, searching several candidate paths.
DynamicLibrary _loadLibrary() {
  if (Platform.isMacOS) {
    final candidates = [
      // Bundled in app (production — Flutter copies dylibs next to the executable)
      'libqjsbridge.dylib',
      // Development: relative to the current working directory (package root)
      '${Directory.current.path}/packages/yourssh_script_engine/assets/native/macos/libqjsbridge.dylib',
      // Absolute fallback (helpful when tests run from a different cwd)
      '${Platform.environment['HOME']}/Documents/Personal/yourssh/packages/yourssh_script_engine/assets/native/macos/libqjsbridge.dylib',
      // Absolute path from known project structure
      '/Users/thangnguyen/Documents/Personal/yourssh/packages/yourssh_script_engine/assets/native/macos/libqjsbridge.dylib',
    ];
    for (final path in candidates) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {}
    }
    throw UnsupportedError('Cannot find libqjsbridge.dylib — tried: $candidates');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libqjsbridge.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('qjsbridge.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// The loaded native library — exposed as public so QuickJsRuntime can look up
/// the callback-taking [qjs_register_host_fn] binding which requires a
/// [NativeCallable] and must be resolved in the runtime class.
final DynamicLibrary lib = _loadLibrary();

// ---------------------------------------------------------------------------
// Opaque pointer type
// ---------------------------------------------------------------------------

/// Opaque C struct representing a QuickJS context.
final class QjsContextOpaque extends Opaque {}

typedef QjsContextPtr = Pointer<QjsContextOpaque>;

// ---------------------------------------------------------------------------
// Native function type aliases (C side)
// ---------------------------------------------------------------------------

typedef _ContextNewNative = QjsContextPtr Function();
typedef _ContextFreeNative = Void Function(QjsContextPtr);
typedef _EvalNative = Int32 Function(
    QjsContextPtr, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetExceptionNative = Pointer<Utf8> Function(QjsContextPtr);
typedef _StringFreeNative = Void Function(Pointer<Utf8>);
typedef _CallFnNative = Pointer<Utf8> Function(
    QjsContextPtr, Pointer<Utf8>, Pointer<Utf8>);

// ---------------------------------------------------------------------------
// Dart function type aliases (Dart side)
// ---------------------------------------------------------------------------

typedef QjsContextNewFn = QjsContextPtr Function();
typedef QjsContextFreeFn = void Function(QjsContextPtr);
typedef QjsEvalFn = int Function(
    QjsContextPtr, Pointer<Utf8>, Pointer<Utf8>);
typedef QjsGetExceptionFn = Pointer<Utf8> Function(QjsContextPtr);
typedef QjsStringFreeFn = void Function(Pointer<Utf8>);
typedef QjsCallFnFn = Pointer<Utf8> Function(
    QjsContextPtr, Pointer<Utf8>, Pointer<Utf8>);

// ---------------------------------------------------------------------------
// Resolved bindings
// ---------------------------------------------------------------------------

final QjsContextNewFn qjsContextNew =
    lib.lookupFunction<_ContextNewNative, QjsContextNewFn>('qjs_context_new');

final QjsContextFreeFn qjsContextFree =
    lib.lookupFunction<_ContextFreeNative, QjsContextFreeFn>(
        'qjs_context_free');

final QjsEvalFn qjsEval =
    lib.lookupFunction<_EvalNative, QjsEvalFn>('qjs_eval');

final QjsGetExceptionFn qjsGetException =
    lib.lookupFunction<_GetExceptionNative, QjsGetExceptionFn>(
        'qjs_get_exception');

final QjsStringFreeFn qjsStringFree =
    lib.lookupFunction<_StringFreeNative, QjsStringFreeFn>('qjs_string_free');

final QjsCallFnFn qjsCallFn =
    lib.lookupFunction<_CallFnNative, QjsCallFnFn>('qjs_call_fn');

// Note: qjs_register_host_fn takes a C function-pointer callback and is looked
// up lazily inside QuickJsRuntime where the NativeCallable type is available.
