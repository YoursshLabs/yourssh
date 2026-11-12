/// Low-level Windows named-pipe bindings shared by the YourSSH app's
/// listener and the `yourssh` client. Windows only at run time; importing it
/// elsewhere is harmless.
library;

export 'src/win_pipe.dart';
