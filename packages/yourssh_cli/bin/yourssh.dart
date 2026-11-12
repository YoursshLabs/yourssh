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
    // Same resolve() call as the app: %LOCALAPPDATA%\YourSSH\run and
    // \\.\pipe\yourssh-cli-<SID>.
    ep = CliEndpoint.resolve(
      os: 'windows',
      env: env,
      home: env['USERPROFILE'] ?? '',
      userSid: sid,
    );
    transport = WindowsPipeTransport();
  } else {
    // R10: the app resolves with the same uid, so a fallback dir matches.
    ep = CliEndpoint.resolve(
      os: Platform.isMacOS ? 'macos' : 'linux',
      env: env,
      home: env['HOME'] ?? '',
      uid: currentUid(),
    );
    transport = UnixSocketTransport();
  }
  final code = await runCli(
    argv,
    transport: transport,
    launcher: SystemAppLauncher(),
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
