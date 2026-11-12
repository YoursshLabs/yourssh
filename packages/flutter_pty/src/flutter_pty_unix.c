
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <time.h>
#include <poll.h>
#include <sys/select.h>
#include <pthread.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/wait.h>

#include "forkpty.h"
#include "flutter_pty.h"
#include "pty_flow.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

typedef struct PtyHandle
{
    int ptm;

    int pid;

    PtyFlow flow;

} PtyHandle;

typedef struct ReadLoopOptions
{
    int fd;

    PtyFlow *flow;

    Dart_Port port;

} ReadLoopOptions;

char *error_message = NULL;

static void *read_loop(void *arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[64 * 1024];
    struct timespec lastPost = {0, 0};

    while (1)
    {
        // Flow control: blocks only once the in-flight budget is used up
        // (one chunk in the legacy ackRead mode).
        pty_flow_wait(options->flow);
        ssize_t n = read(options->fd, buffer, sizeof(buffer));

        if (n < 0)
        {
            // TODO: handle error
            break;
        }

        if (n == 0)
        {
            break;
        }

        struct timespec nowTs;
        clock_gettime(CLOCK_MONOTONIC, &nowTs);
        const long sinceMs = (nowTs.tv_sec - lastPost.tv_sec) * 1000L +
                             (nowTs.tv_nsec - lastPost.tv_nsec) / 1000000L;
        const int flowing = sinceMs < 3;

        // Coalesce: a pty hands out data in small slices (~1 KiB under a
        // flood). Posting each one costs a round trip through the Dart event
        // loop (and, in ack mode, a stall until it is acked), which caps
        // throughput far below what the parser can do. Keep reading while
        // more data is already waiting, up to a nearly full buffer.
        while ((size_t)n + 4096 <= sizeof(buffer))
        {
            // Interactive output after a quiet period never waits. While the
            // stream is flowing (the previous chunk was posted moments ago, or
            // this one is already sizeable) wait a few hundred microseconds
            // for the producer to refill the pty instead of posting a tiny
            // chunk and paying a Dart event-loop turn for it.
            struct timeval tv = {0, (n >= 2048 || flowing) ? 300 : 0};
            fd_set rfds;
            FD_ZERO(&rfds);
            FD_SET(options->fd, &rfds);
            if (select(options->fd + 1, &rfds, NULL, NULL, &tv) <= 0)
            {
                break;
            }
            ssize_t m = read(options->fd, buffer + n, sizeof(buffer) - (size_t)n);
            if (m <= 0)
            {
                break; // EOF/error surfaces on the next blocking read
            }
            n += m;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = n;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        pty_flow_posted(options->flow, (int64_t)n);
        Dart_PostCObject_DL(options->port, &result);
        clock_gettime(CLOCK_MONOTONIC, &lastPost);
    }

    return NULL;
}

static void start_read_thread(int fd, Dart_Port port, PtyFlow *flow)
{
    ReadLoopOptions *options = malloc(sizeof(ReadLoopOptions));

    options->fd = fd;

    options->port = port;

    options->flow = flow;

    pthread_t _thread;

    pthread_create(&_thread, NULL, &read_loop, options);
}

typedef struct WaitExitOptions
{
    int pid;

    Dart_Port port;

    PtyFlow *flow;

} WaitExitOptions;

static void *wait_exit_thread(void *arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    int status;

    waitpid(options->pid, &status, 0);

    // The producer is gone: let a reader that is waiting for credit drain the
    // remaining output and finish instead of blocking forever.
    pty_flow_close(options->flow);

    if (WIFEXITED(status))
    {
        Dart_PostInteger_DL(options->port, WEXITSTATUS(status));
    }
    else if (WIFSIGNALED(status))
    {
        Dart_PostInteger_DL(options->port, -WTERMSIG(status));
    }

    return NULL;
}

static void start_wait_exit_thread(int pid, Dart_Port port, PtyFlow *flow)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;

    options->port = port;

    options->flow = flow;

    pthread_t _thread;

    pthread_create(&_thread, NULL, &wait_exit_thread, options);
}

static void set_environment(char **environment)
{
    if (environment == NULL)
    {
        return;
    }

    while (*environment != NULL)
    {
        putenv(*environment);
        environment++;
    }
}

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    struct winsize ws;

    ws.ws_row = options->rows;
    ws.ws_col = options->cols;

    int ptm;

    int pid = pty_forkpty(&ptm, NULL, NULL, &ws);

    if (pid < 0)
    {
        error_message = "pty_forkpty failed";
        perror("pty_forkpty");
        return NULL;
    }

    if (pid == 0)
    {
        set_environment(options->environment);

        if (options->working_directory != NULL && strlen(options->working_directory) > 0)
        {
            chdir(options->working_directory);
        }

        int ok = execvp(options->executable, options->arguments);

        if (ok < 0)
        {
            perror("execvp");
        }

        // Never fall through into the parent's code in the forked child:
        // exec failed (or returned), so terminate without running atexit
        // handlers or flushing stdio buffers inherited from the parent.
        _exit(127);
    }

    PtyHandle *handle = (PtyHandle *)malloc(sizeof(PtyHandle));

    handle->ptm = ptm;
    handle->pid = pid;
    pty_flow_init(&handle->flow, options->ackRead, options->credit_bytes);

    start_read_thread(ptm, options->stdout_port, &handle->flow);

    start_wait_exit_thread(pid, options->exit_port, &handle->flow);

    return handle;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    write(handle->ptm, buffer, length);
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    // one chunk processed (legacy mode)
    pty_flow_ack_chunk(&handle->flow);
}

FFI_PLUGIN_EXPORT void pty_ack_bytes(PtyHandle *handle, int64_t bytes)
{
    // `bytes` processed: returns that much credit to the reader
    pty_flow_ack_bytes(&handle->flow, bytes);
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    struct winsize ws;

    ws.ws_row = rows;
    ws.ws_col = cols;

    return ioctl(handle->ptm, TIOCSWINSZ, &ws);
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return handle->pid;
}

FFI_PLUGIN_EXPORT char *pty_error(void)
{
    return NULL;
}
