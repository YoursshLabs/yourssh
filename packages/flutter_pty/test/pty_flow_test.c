// Unit test for src/pty_flow.h (built and run by pty_flow_test.dart).
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include "../src/pty_flow.h"

static void test_disabled_never_blocks(void) {
  PtyFlow f; pty_flow_init(&f, 0, 1024);
  for (int i = 0; i < 100; i++) { pty_flow_wait(&f); pty_flow_posted(&f, 4096); }
  assert(!pty_flow_blocked(&f));
}

static void test_chunk_mode(void) {
  PtyFlow f; pty_flow_init(&f, 1, 0);
  pty_flow_wait(&f);
  assert(!pty_flow_blocked(&f));
  pty_flow_posted(&f, 10);
  assert(pty_flow_blocked(&f));
  pty_flow_ack_chunk(&f);
  assert(!pty_flow_blocked(&f));
  pty_flow_ack_chunk(&f); // over-ack clamps
  pty_flow_posted(&f, 10);
  assert(pty_flow_blocked(&f));
}

static void test_credit_budget(void) {
  PtyFlow f; pty_flow_init(&f, 1, 1000);
  pty_flow_posted(&f, 400);
  assert(!pty_flow_blocked(&f));
  pty_flow_posted(&f, 400);
  assert(!pty_flow_blocked(&f)); // 800 < 1000: still may read
  pty_flow_posted(&f, 400);      // overshoot by one chunk
  assert(pty_flow_blocked(&f));
  pty_flow_ack_bytes(&f, 300);   // 900
  assert(pty_flow_blocked(&f) == 0);
  pty_flow_ack_bytes(&f, 5000);  // over-ack clamps to 0
  assert(f.in_flight == 0);
  pty_flow_posted(&f, 1000);
  assert(pty_flow_blocked(&f));
  pty_flow_close(&f);
  assert(!pty_flow_blocked(&f));
}

typedef struct { PtyFlow *f; long total; long chunk; int done; long max_in_flight; } Ctx;

static void *reader(void *p) {
  Ctx *c = p; long sent = 0;
  while (sent < c->total) {
    pty_flow_wait(c->f);
    PTY_FLOW_LOCK(c->f);
    long cur = (long)c->f->in_flight;
    PTY_FLOW_UNLOCK(c->f);
    if (cur > c->max_in_flight) c->max_in_flight = cur;
    long n = c->chunk < c->total - sent ? c->chunk : c->total - sent;
    pty_flow_posted(c->f, n);
    sent += n;
  }
  c->done = 1;
  return NULL;
}

// A consumer on another thread returns credit in batches: the reader must
// finish, never exceed limit + chunk in flight, and never deadlock.
static void test_threaded_stress(void) {
  PtyFlow f; pty_flow_init(&f, 1, 2 * 1024 * 1024);
  Ctx c = { &f, 200L * 1024 * 1024, 64 * 1024, 0, 0 };
  pthread_t t; pthread_create(&t, NULL, reader, &c);
  long acked = 0;
  while (!c.done || acked < c.total) {
    PTY_FLOW_LOCK(&f);
    long pending = (long)f.in_flight;
    PTY_FLOW_UNLOCK(&f);
    if (pending > 0) { pty_flow_ack_bytes(&f, pending); acked += pending; }
    else usleep(10);
    if (c.done) { PTY_FLOW_LOCK(&f); long left=(long)f.in_flight; PTY_FLOW_UNLOCK(&f); if(!left) break; }
  }
  pthread_join(t, NULL);
  assert(c.max_in_flight <= 2 * 1024 * 1024);
}

static void *closer(void *p) { usleep(50000); pty_flow_close((PtyFlow *)p); return NULL; }

static void test_close_releases_blocked_reader(void) {
  PtyFlow f; pty_flow_init(&f, 1, 100);
  pty_flow_posted(&f, 100);
  pthread_t t; pthread_create(&t, NULL, closer, &f);
  pty_flow_wait(&f); // would hang without close
  pthread_join(t, NULL);
}

int main(void) {
  test_disabled_never_blocks();
  test_chunk_mode();
  test_credit_budget();
  test_threaded_stress();
  test_close_releases_blocked_reader();
  printf("ok\n");
  return 0;
}
