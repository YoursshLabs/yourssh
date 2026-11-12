#include <stdio.h>
#include <Windows.h>

#include "flutter_pty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

// Growable UTF-16 buffer used to assemble the command line.
typedef struct WBuf
{
    WCHAR *data;
    size_t len;
    size_t cap;
    BOOL failed;
} WBuf;

static void wbuf_push(WBuf *b, WCHAR c)
{
    if (b->failed)
    {
        return;
    }

    if (b->len + 1 >= b->cap)
    {
        size_t new_cap = b->cap == 0 ? 64 : b->cap * 2;
        WCHAR *grown = realloc(b->data, new_cap * sizeof(WCHAR));

        if (grown == NULL)
        {
            b->failed = TRUE;
            return;
        }

        b->data = grown;
        b->cap = new_cap;
    }

    b->data[b->len++] = c;
}

// Converts a NUL-terminated UTF-8 string to a newly allocated UTF-16 string.
// Returns NULL on allocation or conversion failure.
static WCHAR *utf8_to_wide(const char *s)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);

    if (n <= 0)
    {
        return NULL;
    }

    WCHAR *wide = malloc((size_t)n * sizeof(WCHAR));

    if (wide == NULL)
    {
        return NULL;
    }

    if (MultiByteToWideChar(CP_UTF8, 0, s, -1, wide, n) <= 0)
    {
        free(wide);
        return NULL;
    }

    return wide;
}

// Appends [arg] quoted per the CommandLineToArgvW / MSVCRT rules so the child
// recovers exactly the same argument: wrap in double quotes when the argument
// is empty or contains whitespace or a quote, double backslashes that precede
// a quote (or the closing quote), and escape embedded quotes with a backslash.
static void wbuf_push_quoted(WBuf *b, const WCHAR *arg)
{
    BOOL needs_quotes = arg[0] == 0;

    for (const WCHAR *c = arg; *c != 0 && !needs_quotes; c++)
    {
        if (*c == L' ' || *c == L'\t' || *c == L'\n' || *c == L'\v' || *c == L'"')
        {
            needs_quotes = TRUE;
        }
    }

    if (!needs_quotes)
    {
        for (const WCHAR *c = arg; *c != 0; c++)
        {
            wbuf_push(b, *c);
        }
        return;
    }

    wbuf_push(b, L'"');

    for (const WCHAR *c = arg;; c++)
    {
        size_t backslashes = 0;

        while (*c == L'\\')
        {
            backslashes++;
            c++;
        }

        if (*c == 0)
        {
            // Backslashes before the closing quote must be doubled.
            for (size_t i = 0; i < backslashes * 2; i++)
            {
                wbuf_push(b, L'\\');
            }
            break;
        }

        if (*c == L'"')
        {
            // Double the backslashes and escape the quote itself.
            for (size_t i = 0; i < backslashes * 2 + 1; i++)
            {
                wbuf_push(b, L'\\');
            }
            wbuf_push(b, L'"');
        }
        else
        {
            for (size_t i = 0; i < backslashes; i++)
            {
                wbuf_push(b, L'\\');
            }
            wbuf_push(b, *c);
        }
    }

    wbuf_push(b, L'"');
}

// YOURSSH PATCH (upstream issue #19): the Dart side always puts the
// executable at arguments[0] (Unix execvp convention), but the command line
// for CreateProcessW already starts with `executable`. Appending arguments
// from index 0 duplicated the program name (e.g. "powershell.exe
// powershell.exe"), which PowerShell parsed as -Command and spawned a nested
// shell that never received ConPTY input. The loop below skips arguments[0].
//
// Every piece is converted from UTF-8 to UTF-16 and quoted individually, so
// arguments with spaces or quotes stay one argument and non-ASCII text is not
// mangled by a (WCHAR)char cast. Returns NULL on failure; caller frees.
static LPWSTR build_command(char *executable, char **arguments)
{
    WBuf buf = {0};
    BOOL first = TRUE;

    if (executable != NULL)
    {
        WCHAR *wide = utf8_to_wide(executable);

        if (wide == NULL)
        {
            return NULL;
        }

        wbuf_push_quoted(&buf, wide);
        free(wide);
        first = FALSE;
    }

    if (arguments != NULL && arguments[0] != NULL)
    {
        for (int j = 1; arguments[j] != NULL; j++)
        {
            WCHAR *wide = utf8_to_wide(arguments[j]);

            if (wide == NULL)
            {
                free(buf.data);
                return NULL;
            }

            if (!first)
            {
                wbuf_push(&buf, L' ');
            }

            wbuf_push_quoted(&buf, wide);
            free(wide);
            first = FALSE;
        }
    }

    wbuf_push(&buf, 0);

    if (buf.failed)
    {
        free(buf.data);
        return NULL;
    }

    return buf.data;
}

static LPWSTR build_environment(char **environment)
{
    LPWSTR environment_block = NULL;
    int environment_block_length = 0;

    if (environment != NULL)
    {
        int i = 0;

        while (environment[i] != NULL)
        {
            environment_block_length += (int)strlen(environment[i]) + 1;
            i++;
        }
    }

    environment_block = malloc((environment_block_length + 1) * sizeof(WCHAR));

    if (environment_block != NULL)
    {
        int i = 0;

        if (environment != NULL)
        {
            int j = 0;

            while (environment[j] != NULL)
            {
                int k = 0;

                while (environment[j][k] != 0)
                {
                    environment_block[i] = (WCHAR)environment[j][k];
                    i++;
                    k++;
                }

                environment_block[i++] = 0;

                j++;
            }
        }

        environment_block[i] = 0;
    }

    return environment_block;
}

static LPWSTR build_working_directory(char *working_directory)
{
    if (working_directory == NULL)
    {
        return NULL;
    }

    // UTF-8 -> UTF-16 (the old per-char cast broke non-ASCII paths and read
    // and incremented `i` in one unsequenced expression).
    return utf8_to_wide(working_directory);
}

typedef struct ReadLoopOptions
{
    HANDLE fd;

    Dart_Port port;

    HANDLE hMutex;

    BOOL ackRead;

} ReadLoopOptions;

static DWORD WINAPI read_loop(LPVOID arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[64 * 1024];

    while (1)
    {
        DWORD readlen = 0;

        if (options->ackRead)
        {
            WaitForSingleObject(options->hMutex, INFINITE);
        }

        BOOL ok = ReadFile(options->fd, buffer, sizeof(buffer), &readlen, NULL);

        if (!ok)
        {
            break;
        }

        if (readlen <= 0)
        {
            break;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = readlen;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        Dart_PostCObject_DL(options->port, &result);
    }

    return 0;
}

static void start_read_thread(HANDLE fd, Dart_Port port, HANDLE mutex, BOOL ackRead)
{
    ReadLoopOptions *options = malloc(sizeof(ReadLoopOptions));

    options->fd = fd;
    options->port = port;
    options->hMutex = mutex;
    options->ackRead = ackRead;

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, read_loop, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
}

typedef struct WaitExitOptions
{
    HANDLE pid;

    Dart_Port port;

    HANDLE hMutex;
} WaitExitOptions;

static DWORD WINAPI wait_exit_thread(LPVOID arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    DWORD exit_code = 0;

    WaitForSingleObject(options->pid, INFINITE);

    GetExitCodeProcess(options->pid, &exit_code);

    CloseHandle(options->pid);
    CloseHandle(options->hMutex);

    Dart_PostInteger_DL(options->port, exit_code);

    return 0;
}

static void start_wait_exit_thread(HANDLE pid, Dart_Port port, HANDLE mutex)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;
    options->port = port;
    options->hMutex = mutex;

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, wait_exit_thread, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
}

typedef struct PtyHandle
{
    PHANDLE inputWriteSide;

    PHANDLE outputReadSide;

    HPCON hPty;

    DWORD dwProcessId;

    BOOL ackRead;

    HANDLE hMutex;

} PtyHandle;

char *error_message = NULL;

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    HANDLE inputReadSide = NULL;
    HANDLE inputWriteSide = NULL;

    HANDLE outputReadSide = NULL;
    HANDLE outputWriteSide = NULL;

    if (!CreatePipe(&inputReadSide, &inputWriteSide, NULL, 0))
    {
        error_message = "Failed to create input pipe";
        return NULL;
    }

    if (!CreatePipe(&outputReadSide, &outputWriteSide, NULL, 0))
    {
        error_message = "Failed to create output pipe";
        return NULL;
    }

    COORD size;

    size.X = options->cols;
    size.Y = options->rows;

    HPCON hPty;

    HRESULT result = CreatePseudoConsole(size, inputReadSide, outputWriteSide, 0, &hPty);

    if (FAILED(result))
    {
        error_message = "Failed to create pseudo console";
        return NULL;
    }

    STARTUPINFOEX startupInfo;

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.StartupInfo.cb = sizeof(startupInfo);

    startupInfo.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startupInfo.StartupInfo.hStdInput = NULL;
    startupInfo.StartupInfo.hStdOutput = NULL;
    startupInfo.StartupInfo.hStdError = NULL;

    SIZE_T bytesRequired;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytesRequired);
    startupInfo.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)malloc(bytesRequired);

    BOOL ok = InitializeProcThreadAttributeList(startupInfo.lpAttributeList, 1, 0, &bytesRequired);

    if (!ok)
    {
        error_message = "Failed to initialize proc thread attribute list";
        return NULL;
    }

    ok = UpdateProcThreadAttribute(startupInfo.lpAttributeList,
                                   0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   hPty,
                                   sizeof(hPty),
                                   NULL,
                                   NULL);

    if (!ok)
    {
        error_message = "Failed to update proc thread attribute list";
        return NULL;
    }

    LPWSTR command = build_command(options->executable, options->arguments);

    LPWSTR environment_block = build_environment(options->environment);

    LPWSTR working_directory = build_working_directory(options->working_directory);

    PROCESS_INFORMATION processInfo;
    ZeroMemory(&processInfo, sizeof(processInfo));

    Sleep(1000);

    ok = CreateProcessW(NULL,
                        command,
                        NULL,
                        NULL,
                        FALSE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                        environment_block,
                        working_directory,
                        &startupInfo.StartupInfo,
                        &processInfo);

    if (command != NULL)
    {
        free(command);
    }

    if (environment_block != NULL)
    {
        free(environment_block);
    }

    if (working_directory != NULL)
    {
        free(working_directory);
    }

    if (!ok)
    {
        error_message = "Failed to create process";
        DWORD error = GetLastError();
        printf("error no: %d\n", error);
        return NULL;
    }

    // free(startupInfo.lpAttributeList);

    // CloseHandle(processInfo.hThread);

    HANDLE mutex = CreateSemaphore(
        NULL, // default security attributes
        1,    // initial count
        1,    // maximum count
        NULL);

    start_read_thread(outputReadSide, options->stdout_port, mutex, options->ackRead);

    start_wait_exit_thread(processInfo.hProcess, options->exit_port, mutex);

    PtyHandle *pty = malloc(sizeof(PtyHandle));

    if (pty == NULL)
    {
        error_message = "Failed to allocate pty handle";
        return NULL;
    }

    pty->inputWriteSide = inputWriteSide;
    pty->outputReadSide = outputReadSide;
    pty->hPty = hPty;
    pty->dwProcessId = processInfo.dwProcessId;
    pty->ackRead = options->ackRead;
    pty->hMutex = mutex;

    return pty;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    DWORD bytesWritten;

    WriteFile(handle->inputWriteSide, buffer, length, &bytesWritten, NULL);

    FlushFileBuffers(handle->inputWriteSide);

    return;
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    if (handle->ackRead)
    {
        ReleaseSemaphore(handle->hMutex, 1, NULL);
    }
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    COORD size;

    size.X = cols;
    size.Y = rows;

    return ResizePseudoConsole(handle->hPty, size);
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return (int)handle->dwProcessId;
}

FFI_PLUGIN_EXPORT char *pty_error()
{
    return error_message;
}
