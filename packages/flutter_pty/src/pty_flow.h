// Credit based flow control between a PTY reader thread and the Dart isolate.
//
// Header only and free of Dart / PTY specifics so it can be unit tested with a
// plain C compiler (see test/pty_flow_test.dart).
//
// Modes (chosen by pty_flow_init):
//   - disabled      ack_read == 0: the reader never waits.
//   - chunk mode    ack_read != 0, credit_bytes <= 0: the reader waits after
//                   every posted chunk until pty_flow_ack_chunk (the original
//                   `ackRead` behaviour).
//   - credit mode   ack_read != 0, credit_bytes > 0: the reader keeps posting
//                   until `credit_bytes` are in flight and only then waits;
//                   pty_flow_ack_bytes returns credit by the number of bytes
//                   Dart finished processing. A chunk may overshoot the limit
//                   by its own size, never more.
//
// One mutex + condition variable; every lock/unlock happens on the same
// thread, so nothing is ever unlocked from another thread.
#ifndef PTY_FLOW_H_
#define PTY_FLOW_H_

#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
typedef CRITICAL_SECTION pty_flow_mutex;
typedef CONDITION_VARIABLE pty_flow_cond;
#define PTY_FLOW_LOCK(f) EnterCriticalSection(&(f)->mu)
#define PTY_FLOW_UNLOCK(f) LeaveCriticalSection(&(f)->mu)
#define PTY_FLOW_WAIT(f) SleepConditionVariableCS(&(f)->cv, &(f)->mu, INFINITE)
#define PTY_FLOW_WAKE(f) WakeAllConditionVariable(&(f)->cv)
#else
#include <pthread.h>
typedef pthread_mutex_t pty_flow_mutex;
typedef pthread_cond_t pty_flow_cond;
#define PTY_FLOW_LOCK(f) pthread_mutex_lock(&(f)->mu)
#define PTY_FLOW_UNLOCK(f) pthread_mutex_unlock(&(f)->mu)
#define PTY_FLOW_WAIT(f) pthread_cond_wait(&(f)->cv, &(f)->mu)
#define PTY_FLOW_WAKE(f) pthread_cond_broadcast(&(f)->cv)
#endif

typedef struct PtyFlow
{
    pty_flow_mutex mu;
    pty_flow_cond cv;
    int enabled;
    int64_t limit;     // bytes; 0 = chunk mode
    int64_t in_flight; // bytes posted and not yet acked (credit mode)
    int64_t chunks;    // chunks posted and not yet acked (chunk mode)
    int closed;        // producer gone / torn down: never block again
} PtyFlow;

static inline void pty_flow_init(PtyFlow *f, int ack_read, int64_t credit_bytes)
{
#ifdef _WIN32
    InitializeCriticalSection(&f->mu);
    InitializeConditionVariable(&f->cv);
#else
    pthread_mutex_init(&f->mu, NULL);
    pthread_cond_init(&f->cv, NULL);
#endif
    f->enabled = ack_read != 0;
    f->limit = credit_bytes > 0 ? credit_bytes : 0;
    f->in_flight = 0;
    f->chunks = 0;
    f->closed = 0;
}

static inline int pty_flow_blocked(const PtyFlow *f)
{
    if (!f->enabled || f->closed)
        return 0;
    return f->limit > 0 ? f->in_flight >= f->limit : f->chunks >= 1;
}

// Reader thread: blocks while the budget is exhausted.
static inline void pty_flow_wait(PtyFlow *f)
{
    if (!f->enabled)
        return;
    PTY_FLOW_LOCK(f);
    while (pty_flow_blocked(f))
        PTY_FLOW_WAIT(f);
    PTY_FLOW_UNLOCK(f);
}

// Reader thread: a chunk of `n` bytes was handed to Dart.
static inline void pty_flow_posted(PtyFlow *f, int64_t n)
{
    if (!f->enabled)
        return;
    PTY_FLOW_LOCK(f);
    f->chunks++;
    f->in_flight += n;
    PTY_FLOW_UNLOCK(f);
}

// Dart: one chunk processed (chunk mode).
static inline void pty_flow_ack_chunk(PtyFlow *f)
{
    if (!f->enabled)
        return;
    PTY_FLOW_LOCK(f);
    if (f->chunks > 0)
        f->chunks--;
    PTY_FLOW_WAKE(f);
    PTY_FLOW_UNLOCK(f);
}

// Dart: `n` bytes processed (credit mode). Over-acking clamps at zero.
static inline void pty_flow_ack_bytes(PtyFlow *f, int64_t n)
{
    if (!f->enabled || n <= 0)
        return;
    PTY_FLOW_LOCK(f);
    f->in_flight = n >= f->in_flight ? 0 : f->in_flight - n;
    PTY_FLOW_WAKE(f);
    PTY_FLOW_UNLOCK(f);
}

// The process is gone or the handle is torn down: release a blocked reader so
// it can drain to EOF and exit instead of waiting for acks forever.
static inline void pty_flow_close(PtyFlow *f)
{
    PTY_FLOW_LOCK(f);
    f->closed = 1;
    PTY_FLOW_WAKE(f);
    PTY_FLOW_UNLOCK(f);
}

#endif
