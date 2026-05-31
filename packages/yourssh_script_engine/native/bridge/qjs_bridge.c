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
  JSValue val = JS_Eval(q->ctx, source, strlen(source), filename, JS_EVAL_TYPE_GLOBAL);
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
  HostFnData* d = malloc(sizeof(HostFnData));
  d->cb = cb;
  d->user_data = user_data;

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
