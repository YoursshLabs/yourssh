#include "qjs_bridge.h"
#include "../quickjs/quickjs.h"
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
static int64_t now_ms(void) { return (int64_t)GetTickCount64(); }
#else
#include <time.h>
static int64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
#endif

#define QJS_MEMORY_LIMIT ((size_t)64 * 1024 * 1024)
#define QJS_STACK_LIMIT ((size_t)512 * 1024)
#define QJS_DEFAULT_TIMEOUT_MS 250

typedef struct { QjsHostCallback cb; void* user_data; } HostFnData;

typedef struct HostFnNode {
  HostFnData data;
  struct HostFnNode* next;
} HostFnNode;

struct QjsContext {
  JSRuntime* rt;
  JSContext* ctx;
  int64_t timeout_ms;
  int64_t deadline_ms;
  int timed_out;
  HostFnNode* host_fns;
};

static int interrupt_handler(JSRuntime* rt, void* opaque) {
  QjsContext* q = (QjsContext*)opaque;
  if (q->deadline_ms > 0 && now_ms() > q->deadline_ms) {
    q->timed_out = 1;
    return 1;
  }
  return 0;
}

static void arm_deadline(QjsContext* q) {
  q->timed_out = 0;
  q->deadline_ms = now_ms() + q->timeout_ms;
}

static void disarm_deadline(QjsContext* q) { q->deadline_ms = 0; }

QjsContext* qjs_context_new(void) {
  QjsContext* q = calloc(1, sizeof(QjsContext));
  q->timeout_ms = QJS_DEFAULT_TIMEOUT_MS;
  q->rt = JS_NewRuntime();
  JS_SetMemoryLimit(q->rt, QJS_MEMORY_LIMIT);
  JS_SetMaxStackSize(q->rt, QJS_STACK_LIMIT);
  JS_SetInterruptHandler(q->rt, interrupt_handler, q);
  q->ctx = JS_NewContext(q->rt);
  return q;
}

void qjs_context_free(QjsContext* q) {
  JS_FreeContext(q->ctx);
  JS_FreeRuntime(q->rt);
  HostFnNode* n = q->host_fns;
  while (n) {
    HostFnNode* next = n->next;
    free(n);
    n = next;
  }
  free(q);
}

void qjs_set_timeout_ms(QjsContext* q, int timeout_ms) {
  q->timeout_ms = timeout_ms > 0 ? timeout_ms : QJS_DEFAULT_TIMEOUT_MS;
}

int qjs_timed_out(QjsContext* q) { return q->timed_out; }

void* qjs_alloc(size_t n) { return malloc(n); }
void qjs_free(void* p) { free(p); }

int qjs_eval(QjsContext* q, const char* source, const char* filename) {
  arm_deadline(q);
  JSValue val = JS_Eval(q->ctx, source, strlen(source), filename, JS_EVAL_TYPE_GLOBAL);
  disarm_deadline(q);
  int ok = !JS_IsException(val);
  JS_FreeValue(q->ctx, val);
  return ok;
}

char* qjs_get_exception(QjsContext* q) {
  JSValue exc = JS_GetException(q->ctx);
  // A thrown object's toString() is plugin code too: bound it by a fresh
  // deadline, but keep an earlier timeout visible to the caller.
  int earlier_timeout = q->timed_out;
  arm_deadline(q);
  const char* str = JS_ToCString(q->ctx, exc);
  disarm_deadline(q);
  q->timed_out |= earlier_timeout;
  char* result;
  if (str) {
    result = strdup(str);
    JS_FreeCString(q->ctx, str);
  } else {
    // The conversion itself threw (or was interrupted): drop that exception.
    JS_FreeValue(q->ctx, JS_GetException(q->ctx));
    result = strdup(q->timed_out ? "timeout" : "unknown error");
  }
  JS_FreeValue(q->ctx, exc);
  return result;
}

void qjs_string_free(char* s) { free(s); }

static JSValue _host_fn_dispatch(JSContext* ctx, JSValueConst this_val,
                                  int argc, JSValueConst* argv, int magic,
                                  JSValue* func_data) {
  int64_t ptr_val;
  JS_ToInt64(ctx, &ptr_val, func_data[0]);
  HostFnData* d = (HostFnData*)(uintptr_t)ptr_val;

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
  HostFnNode* node = malloc(sizeof(HostFnNode));
  node->data.cb = cb;
  node->data.user_data = user_data;
  node->next = q->host_fns;
  q->host_fns = node;
  HostFnData* d = &node->data;

  JSValue data_holder[1];
  data_holder[0] = JS_NewInt64(q->ctx, (int64_t)(uintptr_t)d);

  JSValue fn = JS_NewCFunctionData(q->ctx, _host_fn_dispatch, 1, 0, 1, data_holder);
  JS_SetPropertyStr(q->ctx, bridge, fn_name, fn);
  JS_FreeValue(q->ctx, data_holder[0]);
  JS_FreeValue(q->ctx, bridge);
  JS_FreeValue(q->ctx, global);
}

char* qjs_call_fn(QjsContext* q, const char* fn_name, const char* arg_json) {
  JSValue global = JS_GetGlobalObject(q->ctx);
  JSValue fn = JS_GetPropertyStr(q->ctx, global, fn_name);
  JS_FreeValue(q->ctx, global);
  if (!JS_IsFunction(q->ctx, fn)) { JS_FreeValue(q->ctx, fn); return NULL; }
  JSValue arg = JS_NewString(q->ctx, arg_json ? arg_json : "null");
  arm_deadline(q);
  JSValue ret = JS_Call(q->ctx, fn, JS_UNDEFINED, 1, &arg);
  JS_FreeValue(q->ctx, fn);
  JS_FreeValue(q->ctx, arg);
  if (JS_IsException(ret)) {
    disarm_deadline(q);
    JS_FreeValue(q->ctx, ret);
    return NULL;
  }
  // Converting a non-string result runs plugin code (toString/valueOf/
  // Symbol.toPrimitive), so the deadline stays armed until it is done.
  const char* str = JS_ToCString(q->ctx, ret);
  disarm_deadline(q);
  char* result = NULL;
  if (str) {
    result = strdup(str);
    JS_FreeCString(q->ctx, str);
  } else {
    JS_FreeValue(q->ctx, JS_GetException(q->ctx));
  }
  JS_FreeValue(q->ctx, ret);
  return result;
}
