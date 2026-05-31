#ifndef QJS_BRIDGE_H
#define QJS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QjsContext QjsContext;

QjsContext* qjs_context_new(void);
void        qjs_context_free(QjsContext* ctx);

int   qjs_eval(QjsContext* ctx, const char* source, const char* filename);
char* qjs_get_exception(QjsContext* ctx);
void  qjs_string_free(char* s);

typedef char* (*QjsHostCallback)(const char* arg_json, void* user_data);

void qjs_register_host_fn(QjsContext* ctx,
                           const char* bridge_name,
                           const char* fn_name,
                           QjsHostCallback cb,
                           void* user_data);

char* qjs_call_fn(QjsContext* ctx, const char* fn_name, const char* arg_json);

#ifdef __cplusplus
}
#endif

#endif /* QJS_BRIDGE_H */
