#ifndef QJS_BRIDGE_H
#define QJS_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QjsContext QjsContext;

QjsContext* qjs_context_new(void);
void        qjs_context_free(QjsContext* ctx);

/* Per-call wall-clock budget for qjs_eval / qjs_call_fn (default 250 ms). */
void  qjs_set_timeout_ms(QjsContext* ctx, int timeout_ms);
/* Non-zero if the most recent eval/call was aborted by the deadline. */
int   qjs_timed_out(QjsContext* ctx);

/* Allocator pair for buffers handed from the host to C (callback results).
   The bridge frees them with the same allocator. */
void* qjs_alloc(size_t n);
void  qjs_free(void* p);

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
