import 'dart:ffi';

/// The uid this process runs as (POSIX only; never call on Windows).
int currentUid() => (_getuid ??= DynamicLibrary.process()
    .lookupFunction<Uint32 Function(), int Function()>('getuid'))();

int Function()? _getuid;
