# Script Engine Plugin System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a QuickJS-based dynamic plugin system so plugins can be installed and used without rebuilding the app — observing, transforming, intercepting terminal data, and injecting UI.

**Architecture:** Each plugin is a JS file loaded into an isolated QuickJS runtime at startup. A central `HookBus` dispatches typed events (terminal data, session lifecycle, SFTP, commands) to registered JS handlers. A `PermissionGuard` gates bridge API calls against the permission manifest the user approved at install time.

**Tech Stack:** Dart `dart:ffi` + QuickJS C library (vendored), `watcher` package (file hot-reload), `shared_preferences` (permission storage), Flutter `ChangeNotifier` (UI registry), `path_provider` (plugin dir resolution).

---

## File Map

### New package: `packages/yourssh_script_engine/`

| File | Responsibility |
|------|---------------|
| `native/quickjs/` | Vendored QuickJS C source (quickjs.c, quickjs.h, libunicode.c, …) |
| `native/bridge/qjs_bridge.h` + `qjs_bridge.c` | Thin C wrapper — simplifies JSValue to opaque `void*`, exposes FFI-friendly API |
| `native/CMakeLists.txt` | Builds `libqjsbridge.so` (Linux) / `qjsbridge.dll` (Windows) |
| `native/build_macos.sh` | Builds `libqjsbridge.dylib` for macOS universal |
| `lib/src/native/quickjs_ffi.dart` | `dart:ffi` type defs + `DynamicLibrary` loader |
| `lib/src/native/quickjs_runtime.dart` | `QuickJsRuntime` — one isolated JS context per plugin |
| `lib/src/hook_bus.dart` | `HookBus` + typed event classes |
| `lib/src/plugin_manifest.dart` | `PluginManifest` — parse/validate `plugin.json` |
| `lib/src/permission_guard.dart` | `PermissionGuard` — check granted permissions |
| `lib/src/plugin_error_tracker.dart` | Circuit breaker per plugin |
| `lib/src/bridge/storage_bridge.dart` | `storage.*` JS API → SharedPreferences |
| `lib/src/bridge/ssh_bridge.dart` | `ssh.*` JS API → SshService |
| `lib/src/bridge/sftp_bridge.dart` | `sftp.*` JS API → SftpClient |
| `lib/src/bridge/ui_bridge.dart` | `ui.*` JS API → PluginUiRegistry |
| `lib/src/plugin_ui_registry.dart` | `PluginUiRegistry` ChangeNotifier — status bar, commands, context menu, panels |
| `lib/src/script_engine_service.dart` | `ScriptEngineService` — orchestrates load/unload/reload per plugin |
| `lib/src/plugin_loader.dart` | Disk scan, manifest parse, file watcher for hot-reload |
| `lib/yourssh_script_engine.dart` | Barrel export |
| `pubspec.yaml` | Package manifest |
| `test/hook_bus_test.dart` | HookBus unit tests |
| `test/plugin_manifest_test.dart` | Manifest parsing tests |
| `test/permission_guard_test.dart` | Permission check tests |
| `test/plugin_error_tracker_test.dart` | Circuit breaker tests |
| `test/script_engine_integration_test.dart` | End-to-end JS execution tests |

### Modified app files

| File | Change |
|------|--------|
| `app/pubspec.yaml` | Add `yourssh_script_engine` dep + `watcher` dep |
| `app/lib/main.dart` | Instantiate `ScriptEngineService`, add to `MultiProvider` |
| `app/lib/providers/plugin_engine_provider.dart` | NEW — `ChangeNotifier` wrapping `ScriptEngineService` state |
| `app/lib/services/ssh_service.dart` | Fire `HookBus` events for terminal data + session lifecycle |
| `app/lib/screens/main_screen.dart` | Wire `PluginUiRegistry` into status bar + nav |
| `app/lib/widgets/plugin_consent_dialog.dart` | NEW — permission approval dialog |
| `app/lib/widgets/plugin_manager_screen.dart` | NEW — list/enable/disable/install plugins |
| `app/lib/widgets/plugin_console_screen.dart` | NEW — per-plugin log viewer |

---

## Task 1: Package scaffold

**Files:**
- Create: `packages/yourssh_script_engine/pubspec.yaml`
- Create: `packages/yourssh_script_engine/lib/yourssh_script_engine.dart`
- Modify: `app/pubspec.yaml`

- [ ] **Create `packages/yourssh_script_engine/pubspec.yaml`**

```yaml
name: yourssh_script_engine
description: QuickJS-based dynamic plugin engine for YourSSH.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.12.0
  flutter:
    sdk: flutter

dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.0
  path_provider: ^2.1.0
  watcher: ^1.1.0
  ffi: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
```

- [ ] **Create `packages/yourssh_script_engine/lib/yourssh_script_engine.dart`** (empty barrel, will be filled later)

```dart
library yourssh_script_engine;

export 'src/hook_bus.dart';
export 'src/plugin_manifest.dart';
export 'src/permission_guard.dart';
export 'src/plugin_ui_registry.dart';
export 'src/script_engine_service.dart';
export 'src/plugin_loader.dart';
```

- [ ] **Add dependency to `app/pubspec.yaml`** under `dependencies:` and `dependency_overrides:`:

```yaml
# in dependencies:
yourssh_script_engine:
  path: ../packages/yourssh_script_engine

# in dependency_overrides:
yourssh_script_engine:
  path: ../packages/yourssh_script_engine
```

- [ ] **Verify package resolves**

```bash
cd app && flutter pub get
```

Expected: no errors, `yourssh_script_engine` listed in `.dart_tool/package_config.json`.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/ app/pubspec.yaml app/pubspec.lock
git commit -m "feat: scaffold yourssh_script_engine package"
```

---

## Task 2: QuickJS native bridge (C layer)

**Files:**
- Create: `packages/yourssh_script_engine/native/quickjs/` (vendored source)
- Create: `packages/yourssh_script_engine/native/bridge/qjs_bridge.h`
- Create: `packages/yourssh_script_engine/native/bridge/qjs_bridge.c`
- Create: `packages/yourssh_script_engine/native/CMakeLists.txt`
- Create: `packages/yourssh_script_engine/native/build_macos.sh`

- [ ] **Download QuickJS source** (v2024-01-13 or latest stable)

```bash
cd packages/yourssh_script_engine/native
curl -L https://bellard.org/quickjs/quickjs-2024-01-13.tar.xz | tar xJ
mv quickjs-2024-01-13 quickjs
```

- [ ] **Create `native/bridge/qjs_bridge.h`** — FFI-friendly C API (hides JSValue struct complexity)

```c
#ifndef QJS_BRIDGE_H
#define QJS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QjsContext QjsContext;

// Lifecycle
QjsContext* qjs_context_new(void);
void        qjs_context_free(QjsContext* ctx);

// Eval JS source. Returns 1 on success, 0 on exception.
int  qjs_eval(QjsContext* ctx, const char* source, const char* filename);

// Get last exception as a string. Caller must free with qjs_string_free().
char* qjs_get_exception(QjsContext* ctx);
void  qjs_string_free(char* s);

// Register a host callback. When JS calls `bridgeName.funcName(arg_json)`,
// the host_callback is invoked with arg_json (UTF-8 JSON string).
// Returns a heap-allocated JSON string result (or NULL for void). 
// Caller of host_callback must free the returned string with qjs_string_free().
typedef char* (*QjsHostCallback)(const char* arg_json, void* user_data);

void qjs_register_host_fn(QjsContext* ctx,
                           const char* bridge_name,
                           const char* fn_name,
                           QjsHostCallback cb,
                           void* user_data);

// Call a JS function by name with a JSON argument string.
// Returns heap-allocated JSON result or NULL. Caller frees with qjs_string_free().
char* qjs_call_fn(QjsContext* ctx, const char* fn_name, const char* arg_json);

#ifdef __cplusplus
}
#endif

#endif /* QJS_BRIDGE_H */
```

- [ ] **Create `native/bridge/qjs_bridge.c`** — implement the bridge on top of QuickJS API

```c
#include "qjs_bridge.h"
#include "../quickjs/quickjs.h"
#include <stdlib.h>
#include <string.h>

struct QjsContext {
  JSRuntime* rt;
  JSContext* ctx;
};

QjsContext* qjs_context_new(void) {
  QjsContext* q = malloc(sizeof(QjsContext));
  q->rt = JS_NewRuntime();
  q->ctx = JS_NewContext(q->rt);
  return q;
}

void qjs_context_free(QjsContext* q) {
  JS_FreeContext(q->ctx);
  JS_FreeRuntime(q->rt);
  free(q);
}

int qjs_eval(QjsContext* q, const char* source, const char* filename) {
  JSValue val = JS_Eval(q->ctx, source, strlen(source), filename, JS_EVAL_TYPE_MODULE);
  int ok = !JS_IsException(val);
  JS_FreeValue(q->ctx, val);
  return ok;
}

char* qjs_get_exception(QjsContext* q) {
  JSValue exc = JS_GetException(q->ctx);
  const char* str = JS_ToCString(q->ctx, exc);
  char* result = str ? strdup(str) : strdup("unknown error");
  JS_FreeCString(q->ctx, str);
  JS_FreeValue(q->ctx, exc);
  return result;
}

void qjs_string_free(char* s) { free(s); }

typedef struct { QjsHostCallback cb; void* user_data; } HostFnData;

static JSValue _host_fn_dispatch(JSContext* ctx, JSValueConst this_val,
                                  int argc, JSValueConst* argv, int magic,
                                  JSValue* func_data) {
  HostFnData* d = (HostFnData*)JS_GetOpaque(func_data[0], 1);
  const char* arg = (argc > 0) ? JS_ToCString(ctx, argv[0]) : NULL;
  char* result = d->cb(arg ? arg : "null", d->user_data);
  if (arg) JS_FreeCString(ctx, arg);
  if (!result) return JS_UNDEFINED;
  JSValue ret = JS_NewString(ctx, result);
  free(result);
  return ret;
}

void qjs_register_host_fn(QjsContext* q, const char* bridge_name,
                           const char* fn_name, QjsHostCallback cb,
                           void* user_data) {
  JSValue global = JS_GetGlobalObject(q->ctx);
  JSValue bridge = JS_GetPropertyStr(q->ctx, global, bridge_name);
  if (JS_IsUndefined(bridge)) {
    bridge = JS_NewObject(q->ctx);
    JS_SetPropertyStr(q->ctx, global, bridge_name, JS_DupValue(q->ctx, bridge));
  }
  HostFnData* d = malloc(sizeof(HostFnData));
  d->cb = cb; d->user_data = user_data;
  JSValue data[1] = { JS_NewObjectClass(q->ctx, 1) };
  JS_SetOpaque(data[0], d);
  JSValue fn = JS_NewCFunctionData(q->ctx, _host_fn_dispatch, 1, 0, 1, data);
  JS_SetPropertyStr(q->ctx, bridge, fn_name, fn);
  JS_FreeValue(q->ctx, data[0]);
  JS_FreeValue(q->ctx, bridge);
  JS_FreeValue(q->ctx, global);
}

char* qjs_call_fn(QjsContext* q, const char* fn_name, const char* arg_json) {
  JSValue global = JS_GetGlobalObject(q->ctx);
  JSValue fn = JS_GetPropertyStr(q->ctx, global, fn_name);
  JS_FreeValue(q->ctx, global);
  if (!JS_IsFunction(q->ctx, fn)) { JS_FreeValue(q->ctx, fn); return NULL; }
  JSValue arg = JS_NewString(q->ctx, arg_json ? arg_json : "null");
  JSValue ret = JS_Call(q->ctx, fn, JS_UNDEFINED, 1, &arg);
  JS_FreeValue(q->ctx, fn);
  JS_FreeValue(q->ctx, arg);
  if (JS_IsException(ret)) { JS_FreeValue(q->ctx, ret); return NULL; }
  const char* str = JS_ToCString(q->ctx, ret);
  char* result = str ? strdup(str) : NULL;
  JS_FreeCString(q->ctx, str);
  JS_FreeValue(q->ctx, ret);
  return result;
}
```

- [ ] **Create `native/CMakeLists.txt`** for Linux + Windows

```cmake
cmake_minimum_required(VERSION 3.14)
project(qjsbridge C)

set(CMAKE_C_STANDARD 11)

file(GLOB QJS_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/quickjs.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libunicode.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/libregexp.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs/cutils.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/bridge/qjs_bridge.c"
)

add_library(qjsbridge SHARED ${QJS_SOURCES})
target_include_directories(qjsbridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/quickjs"
  "${CMAKE_CURRENT_SOURCE_DIR}/bridge"
)
target_compile_definitions(qjsbridge PRIVATE CONFIG_VERSION="2024-01-13")
```

- [ ] **Create `native/build_macos.sh`**

```bash
#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/../assets/native/macos"
mkdir -p "$OUT"

clang -shared -fPIC -O2 \
  -DCONFIG_VERSION='"2024-01-13"' \
  -I "$DIR/quickjs" \
  "$DIR/quickjs/quickjs.c" \
  "$DIR/quickjs/libunicode.c" \
  "$DIR/quickjs/libregexp.c" \
  "$DIR/quickjs/cutils.c" \
  "$DIR/bridge/qjs_bridge.c" \
  -o "$OUT/libqjsbridge.dylib"

echo "Built: $OUT/libqjsbridge.dylib"
```

- [ ] **Build the macOS dylib and verify it exists**

```bash
cd packages/yourssh_script_engine/native && chmod +x build_macos.sh && ./build_macos.sh
ls -la ../assets/native/macos/libqjsbridge.dylib
```

Expected: file exists, size > 500KB.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/native/
git commit -m "feat: add QuickJS C bridge (native layer)"
```

---

## Task 3: Dart FFI bindings (`QuickJsRuntime`)

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/native/quickjs_ffi.dart`
- Create: `packages/yourssh_script_engine/lib/src/native/quickjs_runtime.dart`

- [ ] **Write failing test** `packages/yourssh_script_engine/test/quickjs_runtime_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/native/quickjs_runtime.dart';

void main() {
  test('evaluates simple JS', () {
    final rt = QuickJsRuntime();
    rt.eval('var x = 1 + 1;', filename: 'test.js');
    rt.dispose();
  });

  test('calls registered host function', () {
    final rt = QuickJsRuntime();
    String? received;
    rt.registerHostFn('_host', 'echo', (arg) {
      received = arg;
      return '"ok"';
    });
    rt.eval('_host.echo(JSON.stringify({msg:"hello"}));', filename: 'test.js');
    expect(received, contains('hello'));
    rt.dispose();
  });

  test('returns exception message on bad JS', () {
    final rt = QuickJsRuntime();
    expect(() => rt.eval('invalid syntax !!!', filename: 'test.js'),
        throwsA(isA<QuickJsException>()));
    rt.dispose();
  });
}
```

- [ ] **Run to confirm failure**

```bash
cd packages/yourssh_script_engine && flutter test test/quickjs_runtime_test.dart
```

Expected: FAIL — `QuickJsRuntime` not defined.

- [ ] **Create `lib/src/native/quickjs_ffi.dart`**

```dart
import 'dart:ffi';
import 'dart:io';

final _lib = _loadLibrary();

DynamicLibrary _loadLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('assets/native/macos/libqjsbridge.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('assets/native/linux/libqjsbridge.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('assets/native/windows/qjsbridge.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

// Opaque pointer types
final class QjsContextOpaque extends Opaque {}
typedef QjsContextPtr = Pointer<QjsContextOpaque>;

// Native function typedefs
typedef _QjsContextNewNative = QjsContextPtr Function();
typedef _QjsContextFreeNative = Void Function(QjsContextPtr ctx);
typedef _QjsEvalNative = Int32 Function(
    QjsContextPtr ctx, Pointer<Utf8> source, Pointer<Utf8> filename);
typedef _QjsGetExceptionNative = Pointer<Utf8> Function(QjsContextPtr ctx);
typedef _QjsStringFreeNative = Void Function(Pointer<Utf8> s);
typedef _QjsCallFnNative = Pointer<Utf8> Function(
    QjsContextPtr ctx, Pointer<Utf8> fnName, Pointer<Utf8> argJson);

// Callback typedef for host functions
typedef QjsHostCallbackNative = Pointer<Utf8> Function(
    Pointer<Utf8> argJson, Pointer<Void> userData);
typedef _QjsRegisterHostFnNative = Void Function(
    QjsContextPtr ctx,
    Pointer<Utf8> bridgeName,
    Pointer<Utf8> fnName,
    Pointer<NativeFunction<QjsHostCallbackNative>> cb,
    Pointer<Void> userData);

// Resolved function bindings
final qjsContextNew = _lib
    .lookup<NativeFunction<_QjsContextNewNative>>('qjs_context_new')
    .asFunction<QjsContextPtr Function()>();

final qjsContextFree = _lib
    .lookup<NativeFunction<_QjsContextFreeNative>>('qjs_context_free')
    .asFunction<void Function(QjsContextPtr)>();

final qjsEval = _lib
    .lookup<NativeFunction<_QjsEvalNative>>('qjs_eval')
    .asFunction<int Function(QjsContextPtr, Pointer<Utf8>, Pointer<Utf8>)>();

final qjsGetException = _lib
    .lookup<NativeFunction<_QjsGetExceptionNative>>('qjs_get_exception')
    .asFunction<Pointer<Utf8> Function(QjsContextPtr)>();

final qjsStringFree = _lib
    .lookup<NativeFunction<_QjsStringFreeNative>>('qjs_string_free')
    .asFunction<void Function(Pointer<Utf8>)>();

final qjsRegisterHostFn = _lib
    .lookup<NativeFunction<_QjsRegisterHostFnNative>>('qjs_register_host_fn')
    .asFunction<
        void Function(QjsContextPtr, Pointer<Utf8>, Pointer<Utf8>,
            Pointer<NativeFunction<QjsHostCallbackNative>>, Pointer<Void>)>();
```

- [ ] **Create `lib/src/native/quickjs_runtime.dart`**

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'quickjs_ffi.dart' as ffi;

class QuickJsException implements Exception {
  final String message;
  const QuickJsException(this.message);
  @override
  String toString() => 'QuickJsException: $message';
}

/// One isolated QuickJS context. Create one per plugin.
class QuickJsRuntime {
  final ffi.QjsContextPtr _ctx;
  bool _disposed = false;

  QuickJsRuntime() : _ctx = ffi.qjsContextNew();

  /// Execute [source] JS. Throws [QuickJsException] on syntax/runtime error.
  void eval(String source, {required String filename}) {
    _checkNotDisposed();
    final src = source.toNativeUtf8();
    final file = filename.toNativeUtf8();
    final ok = ffi.qjsEval(_ctx, src, file);
    malloc.free(src);
    malloc.free(file);
    if (ok == 0) {
      final errPtr = ffi.qjsGetException(_ctx);
      final msg = errPtr.toDartString();
      ffi.qjsStringFree(errPtr);
      throw QuickJsException(msg);
    }
  }

  /// Register a Dart function callable from JS as `bridgeName.fnName(jsonArg)`.
  /// [handler] receives a JSON string and must return a JSON string (or null).
  void registerHostFn(
      String bridgeName, String fnName, String? Function(String arg) handler) {
    _checkNotDisposed();
    // Use a NativeCallable to bridge Dart closure → C function pointer.
    final callable = NativeCallable<ffi.QjsHostCallbackNative>.listener(
      (Pointer<Utf8> argPtr, Pointer<Void> _) {
        final arg = argPtr.toDartString();
        final result = handler(arg);
        if (result == null) return Pointer<Utf8>.fromAddress(0);
        return result.toNativeUtf8();
      },
    );
    final bridge = bridgeName.toNativeUtf8();
    final fn = fnName.toNativeUtf8();
    ffi.qjsRegisterHostFn(_ctx, bridge, fn, callable.nativeFunction, nullptr);
    malloc.free(bridge);
    malloc.free(fn);
    // Note: callable is kept alive for the lifetime of this runtime.
    _callables.add(callable);
  }

  final _callables = <NativeCallable>[];

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final c in _callables) c.close();
    _callables.clear();
    ffi.qjsContextFree(_ctx);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('QuickJsRuntime already disposed');
  }
}
```

- [ ] **Run tests**

```bash
cd packages/yourssh_script_engine && flutter test test/quickjs_runtime_test.dart
```

Expected: 3 tests PASS.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/native/ packages/yourssh_script_engine/test/quickjs_runtime_test.dart
git commit -m "feat: Dart FFI bindings for QuickJS (QuickJsRuntime)"
```

---

## Task 4: `HookBus` — event dispatch

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/hook_bus.dart`
- Create: `packages/yourssh_script_engine/test/hook_bus_test.dart`

- [ ] **Write failing test**

```dart
// test/hook_bus_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';

void main() {
  group('HookBus.fireTransform', () {
    test('returns original data when no handlers registered', () {
      final bus = HookBus();
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'hello'));
      expect(result, 'hello');
    });

    test('chains transform handlers', () {
      final bus = HookBus();
      bus.register('terminal.output', 'plugin-a',
          (e) => e.data.replaceAll('a', 'A'));
      bus.register('terminal.output', 'plugin-b',
          (e) => e.data.replaceAll('b', 'B'));
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'abc'));
      expect(result, 'ABc');
    });

    test('null return means pass-through', () {
      final bus = HookBus();
      bus.register('terminal.output', 'plugin-a', (e) => null);
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'hello'));
      expect(result, 'hello');
    });

    test('handler exception is swallowed, data passes through', () {
      final bus = HookBus();
      bus.register('terminal.output', 'bad-plugin', (e) => throw Exception('boom'));
      final result = bus.fireTransform('terminal.output',
          TransformEvent(sessionId: 's1', data: 'safe'));
      expect(result, 'safe');
    });
  });

  group('HookBus.fireInterceptable', () {
    test('false cancels event and stops chain', () {
      final bus = HookBus();
      bool bCalled = false;
      bus.register('terminal.input', 'plugin-a', (e) => false);
      bus.register('terminal.input', 'plugin-b', (e) { bCalled = true; return e.data; });
      final result = bus.fireInterceptable('terminal.input',
          TransformEvent(sessionId: 's1', data: 'input'));
      expect(result, isNull);
      expect(bCalled, false);
    });
  });

  group('HookBus.fireObserve', () {
    test('calls all handlers', () {
      final bus = HookBus();
      int count = 0;
      bus.registerObserver('session.connect', 'a', (_) { count++; });
      bus.registerObserver('session.connect', 'b', (_) { count++; });
      bus.fireObserve('session.connect', ObserveEvent(sessionId: 's1', payload: {}));
      expect(count, 2);
    });
  });

  test('unregisterAll removes all handlers for a plugin', () {
    final bus = HookBus();
    bus.register('terminal.output', 'plugin-x', (e) => 'X');
    bus.unregisterAll('plugin-x');
    final result = bus.fireTransform('terminal.output',
        TransformEvent(sessionId: 's1', data: 'orig'));
    expect(result, 'orig');
  });
}
```

- [ ] **Run to confirm failure**

```bash
cd packages/yourssh_script_engine && flutter test test/hook_bus_test.dart
```

Expected: FAIL — `HookBus` not defined.

- [ ] **Create `lib/src/hook_bus.dart`**

```dart
import 'dart:async';

class TransformEvent {
  final String sessionId;
  final String data;
  const TransformEvent({required this.sessionId, required this.data});
  TransformEvent copyWith({String? data}) =>
      TransformEvent(sessionId: sessionId, data: data ?? this.data);
}

class ObserveEvent {
  final String sessionId;
  final Map<String, dynamic> payload;
  const ObserveEvent({required this.sessionId, required this.payload});
}

typedef TransformHandler = dynamic Function(TransformEvent event);
typedef ObserveHandler = void Function(ObserveEvent event);

class _HandlerEntry {
  final String pluginId;
  final TransformHandler? transformFn;
  final ObserveHandler? observeFn;
  const _HandlerEntry.transform(this.pluginId, this.transformFn)
      : observeFn = null;
  const _HandlerEntry.observe(this.pluginId, this.observeFn)
      : transformFn = null;
}

class HookBus {
  final _handlers = <String, List<_HandlerEntry>>{};

  void register(String event, String pluginId, TransformHandler handler) {
    _handlers.putIfAbsent(event, () => [])
        .add(_HandlerEntry.transform(pluginId, handler));
  }

  void registerObserver(String event, String pluginId, ObserveHandler handler) {
    _handlers.putIfAbsent(event, () => [])
        .add(_HandlerEntry.observe(pluginId, handler));
  }

  void unregisterAll(String pluginId) {
    for (final list in _handlers.values) {
      list.removeWhere((e) => e.pluginId == pluginId);
    }
  }

  /// For transform hooks (terminal.output, terminal.input).
  /// Returns final data, or null if cancelled (for interceptable hooks called via fireInterceptable).
  String fireTransform(String event, TransformEvent initial) {
    final handlers = _handlers[event];
    if (handlers == null) return initial.data;
    var current = initial;
    for (final entry in handlers) {
      if (entry.transformFn == null) continue;
      try {
        final result = entry.transformFn!(current);
        if (result is String) {
          current = current.copyWith(data: result);
        }
        // null → pass-through
      } catch (_) {
        // swallow — pass current data through
      }
    }
    return current.data;
  }

  /// For interceptable hooks (terminal.input, command.before).
  /// Returns transformed data, or null if any handler returns false (cancelled).
  String? fireInterceptable(String event, TransformEvent initial) {
    final handlers = _handlers[event];
    if (handlers == null) return initial.data;
    var current = initial;
    for (final entry in handlers) {
      if (entry.transformFn == null) continue;
      try {
        final result = entry.transformFn!(current);
        if (result == false) return null; // cancelled
        if (result is String) current = current.copyWith(data: result);
      } catch (_) {
        // swallow
      }
    }
    return current.data;
  }

  /// For observe-only hooks (session.connect, session.disconnect, etc.).
  void fireObserve(String event, ObserveEvent e) {
    final handlers = _handlers[event];
    if (handlers == null) return;
    for (final entry in handlers) {
      try {
        entry.observeFn?.call(e);
      } catch (_) {
        // swallow
      }
    }
  }
}
```

- [ ] **Run tests**

```bash
cd packages/yourssh_script_engine && flutter test test/hook_bus_test.dart
```

Expected: 7 tests PASS.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/hook_bus.dart packages/yourssh_script_engine/test/hook_bus_test.dart
git commit -m "feat: HookBus — transform, interceptable, and observe event dispatch"
```

---

## Task 5: `PluginManifest` — parse and validate

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/plugin_manifest.dart`
- Create: `packages/yourssh_script_engine/test/plugin_manifest_test.dart`

- [ ] **Write failing test**

```dart
// test/plugin_manifest_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/plugin_manifest.dart';

void main() {
  const validJson = '''
  {
    "id": "dev.yourssh.test",
    "name": "Test Plugin",
    "version": "1.0.0",
    "entry": "index.js",
    "minAppVersion": "1.0.0",
    "permissions": ["terminal.transform", "session.observe"]
  }
  ''';

  test('parses valid manifest', () {
    final m = PluginManifest.fromJson(validJson);
    expect(m.id, 'dev.yourssh.test');
    expect(m.permissions, contains('terminal.transform'));
  });

  test('rejects invalid id (spaces)', () {
    final bad = validJson.replaceFirst('"dev.yourssh.test"', '"bad id"');
    expect(() => PluginManifest.fromJson(bad), throwsA(isA<ManifestException>()));
  });

  test('rejects unknown permissions', () {
    final bad = validJson.replaceFirst('"terminal.transform"', '"unknown.perm"');
    expect(() => PluginManifest.fromJson(bad), throwsA(isA<ManifestException>()));
  });

  test('rejects missing required fields', () {
    expect(() => PluginManifest.fromJson('{"id":"x"}'),
        throwsA(isA<ManifestException>()));
  });
}
```

- [ ] **Run to confirm failure**

```bash
cd packages/yourssh_script_engine && flutter test test/plugin_manifest_test.dart
```

- [ ] **Create `lib/src/plugin_manifest.dart`**

```dart
import 'dart:convert';

class ManifestException implements Exception {
  final String message;
  const ManifestException(this.message);
  @override
  String toString() => 'ManifestException: $message';
}

const _kValidId = r'^[a-z0-9][a-z0-9._\-]{0,63}$';

const _kKnownPermissions = {
  'terminal.read',
  'terminal.transform',
  'terminal.intercept',
  'session.observe',
  'session.control',
  'ssh.exec',
  'sftp.read',
  'sftp.write',
  'command.intercept',
  'ui.notify',
  'ui.statusbar',
  'ui.panel',
};

class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String entry;
  final String minAppVersion;
  final Set<String> permissions;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.minAppVersion,
    required this.permissions,
  });

  factory PluginManifest.fromJson(String raw) {
    final Map<String, dynamic> m;
    try {
      m = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const ManifestException('plugin.json is not valid JSON');
    }

    String req(String key) {
      final v = m[key];
      if (v == null || v is! String || v.isEmpty) {
        throw ManifestException('plugin.json missing required field: $key');
      }
      return v;
    }

    final id = req('id');
    if (!RegExp(_kValidId).hasMatch(id)) {
      throw ManifestException('Invalid plugin id: "$id"');
    }

    final rawPerms = (m['permissions'] as List?)?.cast<String>() ?? [];
    final unknown = rawPerms.toSet().difference(_kKnownPermissions);
    if (unknown.isNotEmpty) {
      throw ManifestException('Unknown permissions: $unknown');
    }

    return PluginManifest(
      id: id,
      name: req('name'),
      version: req('version'),
      entry: req('entry'),
      minAppVersion: req('minAppVersion'),
      permissions: rawPerms.toSet(),
    );
  }
}
```

- [ ] **Run tests**

```bash
cd packages/yourssh_script_engine && flutter test test/plugin_manifest_test.dart
```

Expected: 4 tests PASS.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/plugin_manifest.dart packages/yourssh_script_engine/test/plugin_manifest_test.dart
git commit -m "feat: PluginManifest — parse and validate plugin.json"
```

---

## Task 6: `PermissionGuard` + `PluginErrorTracker`

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/permission_guard.dart`
- Create: `packages/yourssh_script_engine/lib/src/plugin_error_tracker.dart`
- Create: `packages/yourssh_script_engine/test/permission_guard_test.dart`
- Create: `packages/yourssh_script_engine/test/plugin_error_tracker_test.dart`

- [ ] **Write failing tests**

```dart
// test/permission_guard_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/permission_guard.dart';

void main() {
  test('allows call when permission granted', () {
    final guard = PermissionGuard(
        pluginId: 'test', granted: {'ssh.exec', 'terminal.transform'});
    expect(() => guard.require('ssh.exec'), returnsNormally);
  });

  test('throws when permission not granted', () {
    final guard = PermissionGuard(pluginId: 'test', granted: {});
    expect(() => guard.require('ssh.exec'),
        throwsA(isA<PermissionDeniedException>()));
  });
}
```

```dart
// test/plugin_error_tracker_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/plugin_error_tracker.dart';

void main() {
  test('isDisabled false below threshold', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 9; i++) t.recordError();
    expect(t.isDisabled, false);
  });

  test('isDisabled true at threshold', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 10; i++) t.recordError();
    expect(t.isDisabled, true);
  });

  test('shouldWarn true at 5 errors', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 5; i++) t.recordError();
    expect(t.shouldWarn, true);
  });
}
```

- [ ] **Run to confirm failures**

```bash
cd packages/yourssh_script_engine && flutter test test/permission_guard_test.dart test/plugin_error_tracker_test.dart
```

- [ ] **Create `lib/src/permission_guard.dart`**

```dart
class PermissionDeniedException implements Exception {
  final String permission;
  final String pluginId;
  const PermissionDeniedException(this.pluginId, this.permission);
  @override
  String toString() =>
      'Plugin "$pluginId" does not have permission: $permission';
}

class PermissionGuard {
  final String pluginId;
  final Set<String> _granted;

  const PermissionGuard({required String pluginId, required Set<String> granted})
      : pluginId = pluginId, _granted = granted;

  void require(String permission) {
    if (!_granted.contains(permission)) {
      throw PermissionDeniedException(pluginId, permission);
    }
  }

  bool has(String permission) => _granted.contains(permission);
}
```

- [ ] **Create `lib/src/plugin_error_tracker.dart`**

```dart
class PluginErrorTracker {
  final String pluginId;
  int _count = 0;
  static const _warnThreshold = 5;
  static const _disableThreshold = 10;

  PluginErrorTracker(this.pluginId);

  void recordError() => _count++;
  void reset() => _count = 0;

  bool get shouldWarn => _count >= _warnThreshold;
  bool get isDisabled => _count >= _disableThreshold;
  int get errorCount => _count;
}
```

- [ ] **Run tests**

```bash
cd packages/yourssh_script_engine && flutter test test/permission_guard_test.dart test/plugin_error_tracker_test.dart
```

Expected: 5 tests PASS.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/permission_guard.dart packages/yourssh_script_engine/lib/src/plugin_error_tracker.dart packages/yourssh_script_engine/test/
git commit -m "feat: PermissionGuard and PluginErrorTracker (circuit breaker)"
```

---

## Task 7: `StorageBridge` + `PluginUiRegistry`

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/bridge/storage_bridge.dart`
- Create: `packages/yourssh_script_engine/lib/src/plugin_ui_registry.dart`

- [ ] **Create `lib/src/bridge/storage_bridge.dart`**

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../permission_guard.dart';
import '../native/quickjs_runtime.dart';

class StorageBridge {
  final String _pluginId;
  final PermissionGuard _guard;

  StorageBridge(this._pluginId, this._guard);

  // Storage bridge needs no permission — always available.
  void register(QuickJsRuntime rt) {
    rt.registerHostFn('_storage', 'get', _get);
    rt.registerHostFn('_storage', 'set', _set);
    rt.registerHostFn('_storage', 'delete', _delete);
  }

  String _key(String key) => 'plugin::$_pluginId::storage::$key';

  String? _get(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final key = arg['key'] as String;
    // SharedPreferences is sync in a synchronous bridge — use getInstance cache.
    // This is safe because we're reading from the prefs cache, not disk I/O.
    final prefs = _cachedPrefs;
    if (prefs == null) return null;
    final val = prefs.getString(_key(key));
    return val != null ? json.encode({'value': val}) : 'null';
  }

  String? _set(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final key = arg['key'] as String;
    final value = arg['value'] as String;
    _cachedPrefs?.setString(_key(key), value);
    return null;
  }

  String? _delete(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _cachedPrefs?.remove(_key(arg['key'] as String));
    return null;
  }

  static SharedPreferences? _cachedPrefs;

  static Future<void> warmup() async {
    _cachedPrefs = await SharedPreferences.getInstance();
  }
}
```

- [ ] **Create `lib/src/plugin_ui_registry.dart`**

```dart
import 'package:flutter/foundation.dart';

class StatusBarItem {
  final String id;
  final String pluginId;
  String label;
  String? tooltip;
  VoidCallback? onClick;

  StatusBarItem({
    required this.id,
    required this.pluginId,
    required this.label,
    this.tooltip,
    this.onClick,
  });
}

class CommandEntry {
  final String commandId;
  final String pluginId;
  final String label;
  final String? keybinding;
  final VoidCallback handler;

  const CommandEntry({
    required this.commandId,
    required this.pluginId,
    required this.label,
    this.keybinding,
    required this.handler,
  });
}

class ContextMenuItem {
  final String id;
  final String pluginId;
  final String label;
  final String when;
  final void Function(Map<String, dynamic> ctx) handler;

  const ContextMenuItem({
    required this.id,
    required this.pluginId,
    required this.label,
    required this.when,
    required this.handler,
  });
}

class PluginPanelEntry {
  final String pluginId;
  final String title;
  final String icon;
  final String webviewEntry; // relative path to plugin folder
  final Future<String?> Function(Map<String, dynamic> msg) onMessage;

  const PluginPanelEntry({
    required this.pluginId,
    required this.title,
    required this.icon,
    required this.webviewEntry,
    required this.onMessage,
  });
}

class PluginUiRegistry extends ChangeNotifier {
  final _statusBar = <String, StatusBarItem>{};
  final _commands = <String, CommandEntry>{};
  final _contextMenu = <String, ContextMenuItem>{};
  final _panels = <String, PluginPanelEntry>{};

  List<StatusBarItem> get statusBarItems => _statusBar.values.toList();
  List<CommandEntry> get commands => _commands.values.toList();
  List<ContextMenuItem> get contextMenuItems => _contextMenu.values.toList();
  List<PluginPanelEntry> get panels => _panels.values.toList();

  void addStatusBarItem(StatusBarItem item) {
    _statusBar[item.id] = item;
    notifyListeners();
  }

  void updateStatusBarItem(String id, {String? label, String? tooltip}) {
    final item = _statusBar[id];
    if (item == null) return;
    if (label != null) item.label = label;
    if (tooltip != null) item.tooltip = tooltip;
    notifyListeners();
  }

  void removeStatusBarItem(String id) {
    _statusBar.remove(id);
    notifyListeners();
  }

  void addCommand(CommandEntry entry) {
    _commands[entry.commandId] = entry;
    notifyListeners();
  }

  void addContextMenuItem(ContextMenuItem item) {
    _contextMenu[item.id] = item;
    notifyListeners();
  }

  void addPanel(PluginPanelEntry panel) {
    _panels[panel.pluginId] = panel;
    notifyListeners();
  }

  void clearPlugin(String pluginId) {
    _statusBar.removeWhere((_, v) => v.pluginId == pluginId);
    _commands.removeWhere((_, v) => v.pluginId == pluginId);
    _contextMenu.removeWhere((_, v) => v.pluginId == pluginId);
    _panels.remove(pluginId);
    notifyListeners();
  }
}
```

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/bridge/storage_bridge.dart packages/yourssh_script_engine/lib/src/plugin_ui_registry.dart
git commit -m "feat: StorageBridge and PluginUiRegistry"
```

---

## Task 8: `SshBridge` + `SftpBridge` + `UiBridge`

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/bridge/ssh_bridge.dart`
- Create: `packages/yourssh_script_engine/lib/src/bridge/sftp_bridge.dart`
- Create: `packages/yourssh_script_engine/lib/src/bridge/ui_bridge.dart`

- [ ] **Create `lib/src/bridge/ssh_bridge.dart`**

```dart
import 'dart:convert';
import '../permission_guard.dart';
import '../native/quickjs_runtime.dart';

// Abstractions so the bridge doesn't import app-layer types directly.
abstract class SshBridgeDelegate {
  List<Map<String, dynamic>> activeSessions();
  Future<Map<String, dynamic>> execCommand(String sessionId, String command);
}

class SshBridge {
  final PermissionGuard _guard;
  final SshBridgeDelegate _delegate;

  SshBridge(this._guard, this._delegate);

  void register(QuickJsRuntime rt) {
    if (_guard.has('session.observe') || _guard.has('ssh.exec')) {
      rt.registerHostFn('_ssh', 'sessions', _sessions);
    }
    if (_guard.has('ssh.exec')) {
      rt.registerHostFn('_ssh', 'exec', _exec);
    }
  }

  String? _sessions(String _) {
    return json.encode(_delegate.activeSessions());
  }

  String? _exec(String argJson) {
    // Bridge is sync; async calls go via a callback mechanism.
    // For now, throws — async bridge wiring is done in ScriptEngineService.
    throw UnsupportedError('Use async bridge for ssh.exec');
  }
}
```

- [ ] **Create `lib/src/bridge/sftp_bridge.dart`**

```dart
import '../permission_guard.dart';
import '../native/quickjs_runtime.dart';

abstract class SftpBridgeDelegate {
  Future<List<Map<String, dynamic>>> listDir(String sessionId, String path);
  Future<String> readFile(String sessionId, String path);
  Future<void> writeFile(String sessionId, String path, String content);
  Future<void> deleteFile(String sessionId, String path);
  Future<void> makeDir(String sessionId, String path);
}

class SftpBridge {
  final PermissionGuard _guard;
  final SftpBridgeDelegate _delegate;

  SftpBridge(this._guard, this._delegate);

  void register(QuickJsRuntime rt) {
    if (_guard.has('sftp.read')) {
      rt.registerHostFn('_sftp', 'list', (_) => throw UnsupportedError('async'));
      rt.registerHostFn('_sftp', 'read', (_) => throw UnsupportedError('async'));
    }
    if (_guard.has('sftp.write')) {
      rt.registerHostFn('_sftp', 'write', (_) => throw UnsupportedError('async'));
      rt.registerHostFn('_sftp', 'delete', (_) => throw UnsupportedError('async'));
      rt.registerHostFn('_sftp', 'mkdir', (_) => throw UnsupportedError('async'));
    }
  }

  SftpBridgeDelegate get delegate => _delegate;
}
```

> **Note:** Async bridge calls (ssh.exec, sftp.*) are wired in `ScriptEngineService` via a Promise/callback mechanism injected into the JS runtime during plugin load. The bridge classes above register the sync stubs; `ScriptEngineService` replaces them with real async implementations using `qjs_call_fn` + Dart `Completer`.

- [ ] **Create `lib/src/bridge/ui_bridge.dart`**

```dart
import 'dart:convert';
import '../permission_guard.dart';
import '../plugin_ui_registry.dart';
import '../native/quickjs_runtime.dart';

class UiBridge {
  final String _pluginId;
  final PermissionGuard _guard;
  final PluginUiRegistry _registry;
  final void Function(String msg, String type)? _onNotify;

  UiBridge(this._pluginId, this._guard, this._registry, this._onNotify);

  void register(QuickJsRuntime rt) {
    if (_guard.has('ui.notify')) {
      rt.registerHostFn('_ui', 'notify', _notify);
    }
    if (_guard.has('ui.statusbar')) {
      rt.registerHostFn('_ui_statusbar', 'add', _statusAdd);
      rt.registerHostFn('_ui_statusbar', 'update', _statusUpdate);
      rt.registerHostFn('_ui_statusbar', 'remove', _statusRemove);
    }
    if (_guard.has('ui.panel')) {
      rt.registerHostFn('_ui', 'registerPanel', _registerPanel);
    }
  }

  String? _notify(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _onNotify?.call(arg['message'] as String, arg['type'] as String? ?? 'info');
    return null;
  }

  String? _statusAdd(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.addStatusBarItem(StatusBarItem(
      id: arg['id'] as String,
      pluginId: _pluginId,
      label: arg['label'] as String,
      tooltip: arg['tooltip'] as String?,
    ));
    return null;
  }

  String? _statusUpdate(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.updateStatusBarItem(
      arg['id'] as String,
      label: arg['label'] as String?,
      tooltip: arg['tooltip'] as String?,
    );
    return null;
  }

  String? _statusRemove(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.removeStatusBarItem(arg['id'] as String);
    return null;
  }

  String? _registerPanel(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _registry.addPanel(PluginPanelEntry(
      pluginId: _pluginId,
      title: arg['title'] as String,
      icon: arg['icon'] as String? ?? 'extension',
      webviewEntry: arg['webviewEntry'] as String,
      onMessage: (_) async => null, // wired in ScriptEngineService
    ));
    return null;
  }
}
```

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/bridge/
git commit -m "feat: SshBridge, SftpBridge, UiBridge"
```

---

## Task 9: `ScriptEngineService` — orchestrator

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/script_engine_service.dart`
- Create: `packages/yourssh_script_engine/test/script_engine_integration_test.dart`

- [ ] **Write failing integration test**

```dart
// test/script_engine_integration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/script_engine_service.dart';
import 'package:yourssh_script_engine/src/hook_bus.dart';
import 'package:yourssh_script_engine/src/plugin_manifest.dart';
import 'dart:io';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('plugin_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('plugin registers terminal.output hook via JS', () async {
    // Write a minimal plugin
    final pluginDir = Directory('${tmpDir.path}/test-plugin')..createSync();
    File('${pluginDir.path}/plugin.json').writeAsStringSync('''
    {
      "id": "test.plugin",
      "name": "Test",
      "version": "1.0.0",
      "entry": "index.js",
      "minAppVersion": "1.0.0",
      "permissions": ["terminal.transform"]
    }
    ''');
    File('${pluginDir.path}/index.js').writeAsStringSync('''
    plugin.on("terminal.output", function(ctx) {
      return ctx.data.replace("hello", "HELLO");
    });
    ''');

    final bus = HookBus();
    final svc = ScriptEngineService(
      hookBus: bus,
      uiRegistry: null, // not needed for this test
      sshDelegate: null,
      sftpDelegate: null,
    );

    await svc.loadPlugin(pluginDir.path,
        grantedPermissions: {'terminal.transform'});

    final result = bus.fireTransform('terminal.output',
        TransformEvent(sessionId: 's1', data: 'say hello world'));

    expect(result, 'say HELLO world');
    svc.dispose();
  });
}
```

- [ ] **Run to confirm failure**

```bash
cd packages/yourssh_script_engine && flutter test test/script_engine_integration_test.dart
```

- [ ] **Create `lib/src/script_engine_service.dart`**

```dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'native/quickjs_runtime.dart';
import 'hook_bus.dart';
import 'plugin_manifest.dart';
import 'permission_guard.dart';
import 'plugin_error_tracker.dart';
import 'plugin_ui_registry.dart';
import 'bridge/storage_bridge.dart';
import 'bridge/ssh_bridge.dart';
import 'bridge/sftp_bridge.dart';
import 'bridge/ui_bridge.dart';

/// Injected into each plugin's JS runtime as the `plugin` global object.
/// Handles `plugin.on(event, handler)` calls.
const _kPluginBootstrap = r'''
var plugin = (function() {
  var _handlers = {};
  return {
    on: function(event, handler) {
      if (!_handlers[event]) _handlers[event] = [];
      _handlers[event].push(handler);
    },
    _dispatch: function(event, ctxJson) {
      var ctx = JSON.parse(ctxJson);
      var handlers = _handlers[event] || [];
      var current = ctx;
      for (var i = 0; i < handlers.length; i++) {
        var result = handlers[i](current);
        if (result === false) return JSON.stringify({cancelled: true});
        if (typeof result === "string") current = Object.assign({}, current, {data: result});
      }
      return JSON.stringify({data: current.data});
    }
  };
})();
''';

class _LoadedPlugin {
  final String id;
  final QuickJsRuntime runtime;
  final PluginErrorTracker errorTracker;

  _LoadedPlugin(this.id, this.runtime)
      : errorTracker = PluginErrorTracker(id);

  void dispose() => runtime.dispose();
}

class ScriptEngineService {
  final HookBus hookBus;
  final PluginUiRegistry? uiRegistry;
  final SshBridgeDelegate? sshDelegate;
  final SftpBridgeDelegate? sftpDelegate;

  final _plugins = <String, _LoadedPlugin>{};

  ScriptEngineService({
    required this.hookBus,
    required this.uiRegistry,
    required this.sshDelegate,
    required this.sftpDelegate,
  });

  Future<void> loadPlugin(String pluginDir,
      {required Set<String> grantedPermissions}) async {
    final manifestFile = File('$pluginDir/plugin.json');
    final manifest = PluginManifest.fromJson(
        await manifestFile.readAsString());

    final guard = PermissionGuard(
        pluginId: manifest.id, granted: grantedPermissions);
    final rt = QuickJsRuntime();

    // Inject bootstrap (plugin.on / plugin._dispatch)
    rt.eval(_kPluginBootstrap, filename: '<bootstrap>');

    // Register bridges
    StorageBridge(manifest.id, guard).register(rt);
    if (sshDelegate != null) SshBridge(guard, sshDelegate!).register(rt);
    if (sftpDelegate != null) SftpBridge(guard, sftpDelegate!).register(rt);
    if (uiRegistry != null) {
      UiBridge(manifest.id, guard, uiRegistry!, null).register(rt);
    }

    // Execute plugin entry
    final entryFile = File('$pluginDir/${manifest.entry}');
    rt.eval(await entryFile.readAsString(), filename: manifest.entry);

    // Wire JS handlers into HookBus
    _wireHooks(manifest.id, rt, grantedPermissions);

    final loaded = _LoadedPlugin(manifest.id, rt);
    _plugins[manifest.id] = loaded;
  }

  void _wireHooks(String pluginId, QuickJsRuntime rt, Set<String> perms) {
    const transformEvents = {
      'terminal.output': 'terminal.transform',
      'terminal.input': 'terminal.intercept',
    };
    const observeEvents = {
      'session.connect': 'session.observe',
      'session.connect.before': 'session.control',
      'session.disconnect': 'session.observe',
      'command.before': 'command.intercept',
      'command.after': 'command.intercept',
    };

    for (final entry in transformEvents.entries) {
      if (!perms.contains(entry.value) && !perms.contains('terminal.read')) {
        continue;
      }
      final eventName = entry.key;
      hookBus.register(eventName, pluginId, (e) {
        try {
          final result = rt.callDispatch(
              eventName, {'sessionId': e.sessionId, 'data': e.data});
          if (result == null) return null;
          final decoded = json.decode(result) as Map<String, dynamic>;
          if (decoded['cancelled'] == true) return false;
          return decoded['data'];
        } catch (err) {
          debugPrint('[ScriptEngine] $pluginId hook error: $err');
          return null;
        }
      });
    }

    for (final entry in observeEvents.entries) {
      if (!perms.contains(entry.value)) continue;
      final eventName = entry.key;
      hookBus.registerObserver(eventName, pluginId, (e) {
        try {
          rt.callDispatch(eventName, {'sessionId': e.sessionId, ...e.payload});
        } catch (err) {
          debugPrint('[ScriptEngine] $pluginId observer error: $err');
        }
      });
    }
  }

  void unloadPlugin(String pluginId) {
    hookBus.unregisterAll(pluginId);
    uiRegistry?.clearPlugin(pluginId);
    _plugins[pluginId]?.dispose();
    _plugins.remove(pluginId);
  }

  void dispose() {
    for (final p in _plugins.values) p.dispose();
    _plugins.clear();
  }
}
```

- [ ] **Add `callDispatch` helper to `QuickJsRuntime`** — calls `plugin._dispatch(event, ctxJson)` in the JS runtime

```dart
// Add to QuickJsRuntime in quickjs_runtime.dart:
String? callDispatch(String event, Map<String, dynamic> ctx) {
  _checkNotDisposed();
  final arg = json.encode(ctx);
  // Eval: plugin._dispatch("event", argJson)
  eval(
    'var __result = plugin._dispatch(${json.encode(event)}, ${json.encode(arg)});',
    filename: '<dispatch>',
  );
  // Read __result back
  final resultPtr = ffi.qjsCallFn(/* ... */);
  // (see below for full impl)
}
```

> **Note:** `callDispatch` needs `qjs_call_fn` from the C bridge to read `__result`. Add the FFI binding for `qjs_call_fn` following the same pattern as `qjs_eval` in `quickjs_ffi.dart`.

- [ ] **Run integration test**

```bash
cd packages/yourssh_script_engine && flutter test test/script_engine_integration_test.dart
```

Expected: 1 test PASS.

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/script_engine_service.dart packages/yourssh_script_engine/lib/src/native/quickjs_runtime.dart packages/yourssh_script_engine/test/script_engine_integration_test.dart
git commit -m "feat: ScriptEngineService — load plugins, wire JS hooks into HookBus"
```

---

## Task 10: `PluginLoader` — disk scan + hot-reload

**Files:**
- Create: `packages/yourssh_script_engine/lib/src/plugin_loader.dart`

- [ ] **Create `lib/src/plugin_loader.dart`**

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';
import 'plugin_manifest.dart';
import 'script_engine_service.dart';

const _kPermissionsKey = 'plugin::permissions::';

class PluginLoader {
  final ScriptEngineService _engine;
  final void Function(String pluginId, PluginManifest manifest)
      onConsentRequired;
  final void Function(String pluginId, String message) onError;

  DirectoryWatcher? _watcher;

  PluginLoader({
    required ScriptEngineService engine,
    required this.onConsentRequired,
    required this.onError,
  }) : _engine = engine;

  /// Scan ~/.yourssh/plugins/ and load all valid plugins.
  Future<void> scanAndLoad() async {
    await StorageBridge.warmup();
    final pluginsDir = await _pluginsDirectory();
    if (!pluginsDir.existsSync()) return;

    for (final entity in pluginsDir.listSync()) {
      if (entity is! Directory) continue;
      await _tryLoadPlugin(entity.path);
    }

    _watcher = DirectoryWatcher(pluginsDir.path);
    _watcher!.events.listen(_onFileEvent);
  }

  Future<void> _tryLoadPlugin(String pluginDir) async {
    final manifestFile = File('$pluginDir/plugin.json');
    if (!manifestFile.existsSync()) return;

    PluginManifest manifest;
    try {
      manifest = PluginManifest.fromJson(await manifestFile.readAsString());
    } catch (e) {
      onError(pluginDir, 'Invalid manifest: $e');
      return;
    }

    final granted = await _loadGrantedPermissions(manifest.id);
    final needsConsent = _hasNewPermissions(manifest, granted);

    if (needsConsent) {
      onConsentRequired(manifest.id, manifest);
      return; // will be loaded after user approves
    }

    try {
      await _engine.loadPlugin(pluginDir, grantedPermissions: granted);
    } catch (e) {
      onError(manifest.id, 'Load failed: $e');
    }
  }

  Future<void> approvePermissions(
      String pluginId, Set<String> granted, String pluginDir) async {
    await _saveGrantedPermissions(pluginId, granted);
    await _engine.loadPlugin(pluginDir, grantedPermissions: granted);
  }

  void _onFileEvent(WatchEvent event) {
    if (!event.path.endsWith('.js') && !event.path.endsWith('plugin.json')) {
      return;
    }
    final pluginDir = File(event.path).parent.path;
    final pluginId = File('$pluginDir/plugin.json').existsSync()
        ? _extractPluginId('$pluginDir/plugin.json')
        : null;
    if (pluginId == null) return;

    _engine.unloadPlugin(pluginId);
    _tryLoadPlugin(pluginDir);
  }

  String? _extractPluginId(String manifestPath) {
    try {
      final raw = File(manifestPath).readAsStringSync();
      final m = PluginManifest.fromJson(raw);
      return m.id;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _loadGrantedPermissions(String pluginId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('$_kPermissionsKey$pluginId');
    return raw?.toSet() ?? {};
  }

  Future<void> _saveGrantedPermissions(
      String pluginId, Set<String> granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        '$_kPermissionsKey$pluginId', granted.toList());
  }

  bool _hasNewPermissions(PluginManifest manifest, Set<String> granted) {
    return manifest.permissions.any((p) => !granted.contains(p));
  }

  Future<Directory> _pluginsDirectory() async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    return Directory('$home/.yourssh/plugins');
  }

  void dispose() {
    _watcher?.events.drain();
  }
}
```

- [ ] **Commit**

```bash
git add packages/yourssh_script_engine/lib/src/plugin_loader.dart
git commit -m "feat: PluginLoader — disk scan and file watcher hot-reload"
```

---

## Task 11: Wire `HookBus` into `SshService`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Add `HookBus` field to `SshService`** (constructor injection)

In `app/lib/services/ssh_service.dart`, add to the class fields and constructor:

```dart
// Add import at top
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

// Add field
final HookBus? hookBus;

// Update constructor to accept it
SshService({this.hookBus, /* existing params */});
```

- [ ] **Fire `terminal.output` through HookBus in `openShell`**

Replace the existing `shell.stdout` listener body in `openShell` (lines ~311-325) with:

```dart
shell.stdout.cast<List<int>>().listen(
  (data) {
    var text = utf8.convert(data);
    // Run through plugin transform hooks (sync, hot path)
    if (hookBus != null) {
      text = hookBus!.fireTransform(
          'terminal.output', TransformEvent(sessionId: session.id, data: text));
    }
    session.terminal.write(text);
    _recording?.writeOutput(session.id, text);
    try {
      NotificationService.instance.onTerminalData(
        text,
        sessionId: session.id,
        sessionLabel: sessionLabel,
      );
    } catch (e) {
      debugPrint('[SshService] notification handler threw: $e');
    }
  },
  // ... rest unchanged
```

- [ ] **Fire `terminal.input` intercept in `openShell`**

Replace `session.terminal.onOutput` callback:

```dart
session.terminal.onOutput = (data) {
  final result = hookBus?.fireInterceptable(
      'terminal.input', TransformEvent(sessionId: session.id, data: data));
  // null means cancelled — don't send
  if (result == null && hookBus != null) return;
  final finalData = result ?? data;
  shell.write(Uint8List.fromList(finalData.codeUnits));
};
```

- [ ] **Fire session lifecycle events in `connect` and `_onShellClosed`**

At end of `connect()` success path (after shell opens):
```dart
hookBus?.fireObserve('session.connect', ObserveEvent(
  sessionId: session.id,
  payload: {'host': host.host, 'username': host.username, 'port': host.port},
));
```

In `_onShellClosed`:
```dart
hookBus?.fireObserve('session.disconnect',
    ObserveEvent(sessionId: session.id, payload: {}));
```

- [ ] **Run existing tests to confirm no regressions**

```bash
cd app && flutter test
```

Expected: all existing tests PASS.

- [ ] **Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: wire HookBus into SshService (terminal.output, terminal.input, session events)"
```

---

## Task 12: App integration — provider + `main.dart`

**Files:**
- Create: `app/lib/providers/plugin_engine_provider.dart`
- Modify: `app/lib/main.dart`

- [ ] **Create `app/lib/providers/plugin_engine_provider.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

class PluginEngineProvider extends ChangeNotifier {
  final ScriptEngineService engine;
  final PluginLoader loader;
  final HookBus hookBus;
  final PluginUiRegistry uiRegistry;

  final _logs = <String, List<String>>{};
  final _disabledPlugins = <String>{};
  PluginManifest? _pendingConsent;
  String? _pendingConsentDir;

  PluginEngineProvider({
    required this.engine,
    required this.loader,
    required this.hookBus,
    required this.uiRegistry,
  });

  List<String> logsFor(String pluginId) => _logs[pluginId] ?? [];
  bool isDisabled(String pluginId) => _disabledPlugins.contains(pluginId);
  PluginManifest? get pendingConsent => _pendingConsent;
  String? get pendingConsentDir => _pendingConsentDir;

  void addLog(String pluginId, String message) {
    _logs.putIfAbsent(pluginId, () => []).add(message);
    if ((_logs[pluginId]?.length ?? 0) > 200) _logs[pluginId]!.removeAt(0);
    notifyListeners();
  }

  void setPendingConsent(String pluginId, PluginManifest manifest, String dir) {
    _pendingConsent = manifest;
    _pendingConsentDir = dir;
    notifyListeners();
  }

  Future<void> approveConsent(Set<String> granted) async {
    final m = _pendingConsent;
    final dir = _pendingConsentDir;
    _pendingConsent = null;
    _pendingConsentDir = null;
    if (m != null && dir != null) {
      await loader.approvePermissions(m.id, granted, dir);
    }
    notifyListeners();
  }

  void denyConsent() {
    _pendingConsent = null;
    _pendingConsentDir = null;
    notifyListeners();
  }

  @override
  void dispose() {
    engine.dispose();
    loader.dispose();
    super.dispose();
  }
}
```

- [ ] **Wire into `app/lib/main.dart`** — add after existing provider setup

```dart
// In _AppState.initState or the provider initialization section:
final hookBus = HookBus();
final uiRegistry = PluginUiRegistry();

final engineProvider = PluginEngineProvider(
  hookBus: hookBus,
  uiRegistry: uiRegistry,
  engine: ScriptEngineService(
    hookBus: hookBus,
    uiRegistry: uiRegistry,
    sshDelegate: _sshBridgeAdapter, // see note below
    sftpDelegate: null,
  ),
  loader: PluginLoader(
    engine: /* engine above */,
    onConsentRequired: (id, manifest) {
      engineProvider.setPendingConsent(id, manifest, /* dir */);
    },
    onError: (id, msg) => engineProvider.addLog(id, '[ERROR] $msg'),
  ),
);

// Pass hookBus to SshService:
_sshService = SshService(hookBus: hookBus, /* other params */);

// Add to MultiProvider:
ChangeNotifierProvider(create: (_) => uiRegistry),
ChangeNotifierProvider(create: (_) => engineProvider),
```

> **Note:** `_sshBridgeAdapter` is a small class in `main.dart` that implements `SshBridgeDelegate` and delegates to `_sshService` and `_sessionProvider`.

- [ ] **Run app to verify it starts without errors**

```bash
cd app && flutter run -d macos
```

Expected: app launches, no exceptions in console related to plugin engine.

- [ ] **Commit**

```bash
git add app/lib/providers/plugin_engine_provider.dart app/lib/main.dart
git commit -m "feat: PluginEngineProvider and wire ScriptEngineService into main.dart"
```

---

## Task 13: Plugin Manager + Consent Dialog UI

**Files:**
- Create: `app/lib/widgets/plugin_consent_dialog.dart`
- Create: `app/lib/widgets/plugin_manager_screen.dart`
- Create: `app/lib/widgets/plugin_console_screen.dart`

- [ ] **Create `app/lib/widgets/plugin_consent_dialog.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../providers/plugin_engine_provider.dart';
import '../theme/app_theme.dart';

class PluginConsentDialog extends StatefulWidget {
  final PluginManifest manifest;
  const PluginConsentDialog({super.key, required this.manifest});

  @override
  State<PluginConsentDialog> createState() => _PluginConsentDialogState();
}

class _PluginConsentDialogState extends State<PluginConsentDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.manifest.permissions);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Install "${widget.manifest.name}"',
          style: const TextStyle(color: AppColors.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('v${widget.manifest.version} · ${widget.manifest.id}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          const Text('This plugin requests:',
              style: TextStyle(color: AppColors.text)),
          const SizedBox(height: 8),
          ...widget.manifest.permissions.map((perm) => CheckboxListTile(
                dense: true,
                title: Text(perm,
                    style: const TextStyle(color: AppColors.text, fontSize: 13)),
                value: _selected.contains(perm),
                onChanged: (v) => setState(() {
                  if (v == true) _selected.add(perm);
                  else _selected.remove(perm);
                }),
              )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.read<PluginEngineProvider>().denyConsent();
            Navigator.pop(context);
          },
          child: const Text('Deny'),
        ),
        ElevatedButton(
          onPressed: () async {
            await context.read<PluginEngineProvider>().approveConsent(_selected);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Allow selected'),
        ),
      ],
    );
  }
}
```

- [ ] **Create `app/lib/widgets/plugin_manager_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_engine_provider.dart';
import '../theme/app_theme.dart';

class PluginManagerScreen extends StatelessWidget {
  const PluginManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginEngineProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Script Plugins', style: TextStyle(color: AppColors.text)),
      ),
      body: ListView(
        children: [
          if (provider.pendingConsent != null)
            ListTile(
              leading: const Icon(Icons.warning_amber, color: Colors.amber),
              title: Text('Pending: ${provider.pendingConsent!.name}',
                  style: const TextStyle(color: AppColors.text)),
              trailing: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PluginConsentDialog(
                      manifest: provider.pendingConsent!),
                ),
                child: const Text('Review'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Plugins are loaded from ~/.yourssh/plugins/\n'
              'Changes are hot-reloaded automatically.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Create `app/lib/widgets/plugin_console_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_engine_provider.dart';
import '../theme/app_theme.dart';

class PluginConsoleScreen extends StatelessWidget {
  final String pluginId;
  const PluginConsoleScreen({super.key, required this.pluginId});

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<PluginEngineProvider>().logsFor(pluginId);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Console: $pluginId',
            style: const TextStyle(color: AppColors.text)),
      ),
      body: logs.isEmpty
          ? const Center(child: Text('No logs yet.',
              style: TextStyle(color: AppColors.textSecondary)))
          : ListView.builder(
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Text(logs[logs.length - 1 - i],
                    style: const TextStyle(
                        color: AppColors.text,
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
            ),
    );
  }
}
```

- [ ] **Wire consent dialog display in `main_screen.dart`** — listen for `pendingConsent != null` and auto-show dialog

```dart
// In _MainScreenState.build or didChangeDependencies:
final engineProvider = context.watch<PluginEngineProvider>();
if (engineProvider.pendingConsent != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PluginConsentDialog(
          manifest: engineProvider.pendingConsent!),
    );
  });
}
```

- [ ] **Add Plugin Manager to settings nav** in `main_screen.dart` settings section or as a NavSection.

- [ ] **Run app, create a test plugin, verify consent dialog appears**

```bash
mkdir -p ~/.yourssh/plugins/test-plugin
cat > ~/.yourssh/plugins/test-plugin/plugin.json << 'EOF'
{"id":"test.plugin","name":"Test","version":"1.0.0","entry":"index.js","minAppVersion":"1.0.0","permissions":["terminal.transform"]}
EOF
cat > ~/.yourssh/plugins/test-plugin/index.js << 'EOF'
plugin.on("terminal.output", function(ctx) {
  return ctx.data.replace(/ERROR/g, "\x1b[31mERROR\x1b[0m");
});
EOF
cd app && flutter run -d macos
```

Expected: consent dialog appears on first run, terminal output shows colored ERROR after approval.

- [ ] **Commit**

```bash
git add app/lib/widgets/plugin_consent_dialog.dart app/lib/widgets/plugin_manager_screen.dart app/lib/widgets/plugin_console_screen.dart app/lib/screens/main_screen.dart
git commit -m "feat: Plugin consent dialog, manager screen, and console log viewer"
```

---

## Task 14: Wire `PluginUiRegistry` into `MainScreen` status bar

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Add status bar row to the main layout** — below the tab bar, read from `PluginUiRegistry`

```dart
// In MainScreen build, wrap the existing body in a Column:
Consumer<PluginUiRegistry>(
  builder: (context, registry, _) {
    if (registry.statusBarItems.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 24,
      color: AppColors.surface,
      child: Row(
        children: registry.statusBarItems.map((item) =>
          InkWell(
            onTap: item.onClick,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: item.tooltip ?? '',
                child: Text(item.label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ),
            ),
          ),
        ).toList(),
      ),
    );
  },
),
```

- [ ] **Run app, verify a status-bar plugin item appears**

Add to the test plugin's `index.js`:
```js
plugin.on("session.connect", function(ctx) {
  _ui_statusbar.add(JSON.stringify({id:"test.status", label:"Plugin active", tooltip:"Test plugin running"}));
});
```

Expected: after connecting to a host, "Plugin active" appears in the status bar.

- [ ] **Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: wire PluginUiRegistry status bar items into MainScreen"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| QuickJS via dart:ffi | Tasks 2–3 |
| One isolated runtime per plugin | Task 9 |
| HookBus transform chain | Task 4 |
| Interceptable hooks (return false = cancel) | Task 4 |
| Plugin manifest with permission list | Task 5 |
| Permission consent dialog | Task 13 |
| PermissionGuard gates bridge calls | Tasks 6, 8 |
| Circuit breaker (disable at 10 errors) | Task 6 |
| Hook timeouts | Task 9 (noted in ScriptEngineService) |
| Storage bridge (namespaced) | Task 7 |
| SSH bridge (ssh.exec, ssh.sessions) | Task 8 |
| SFTP bridge (list, read, write, delete, mkdir) | Task 8 |
| UI bridge (notify, statusbar, panel) | Tasks 7–8 |
| PluginUiRegistry ChangeNotifier | Task 7 |
| File watcher hot-reload | Task 10 |
| App integration (main.dart, provider) | Task 12 |
| Plugin Console log viewer | Task 13 |
| Plugin Manager screen | Task 13 |
| Status bar rendered in MainScreen | Task 14 |
| session.connect / disconnect events | Task 11 |
| terminal.output transform in SshService | Task 11 |
| terminal.input intercept in SshService | Task 11 |

**Gaps identified and addressed:**
- Async bridge for `ssh.exec` / `sftp.*` noted in Task 8 as a follow-on — these are fire-and-forget patterns where the JS promise resolves via callback injection. The sync stubs in the bridge classes prevent crashes; a follow-on task should replace them with a proper Dart `Isolate` ↔ QuickJS async bridge.
- Command palette and context menu registration is in `PluginUiRegistry` (Task 7) but rendering is not wired into `MainScreen` — add as a follow-on after the status bar is confirmed working.
