import 'dart:io';

import 'package:yourssh_cli/yourssh_cli.dart';

Future<void> main(List<String> argv) async {
  final env = Platform.environment;
  final CliEndpoint ep;
  final CliTransport transport;
  if (Platform.isWindows) {
    String sid;
    try {
      sid = currentUserSid();
    } on Object catch (e) {
      stderr.writeln('yourssh: cannot determine the current Windows user: $e');
      exit(CliExit.runtime.code);
    }
    // Same resolve() as the app: %LOCALAPPDATA%\YourSSH\run and
    // \\.\pipe\yourssh-cli-<SID> (the -dev variant with YOURSSH_DEV=1).
    ep = CliEndpoint.forCli(os: 'windows', env: env, userSid: sid);
    transport = WindowsPipeTransport();
  } else {
    // R10: the app resolves with the same uid, so a fallback dir matches.
    // YOURSSH_DEV=1 targets a non-release app build (flutter run).
    ep = CliEndpoint.forCli(
        os: Platform.isMacOS ? 'macos' : 'linux', env: env, uid: currentUid());
    transport = UnixSocketTransport();
  }
  final code = await runCli(
    argv,
    transport: transport,
    // A debug build is started with flutter run, never by launching the
    // installed app.
    launcher:
        CliEndpoint.isDevEnv(env) ? DevBuildLauncher() : SystemAppLauncher(),
    endpoint: ep,
    out: stdout,
    err: stderr,
    isTty: stdout.hasTerminal,
    env: env,
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
