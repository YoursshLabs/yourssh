import 'dart:io';

import 'package:yourssh_cli/yourssh_cli.dart';

Future<void> main(List<String> argv) async {
  if (Platform.isWindows) {
    stderr.writeln('yourssh: Windows support arrives in a later build');
    exit(CliExit.unreachable.code);
  }
  final env = Platform.environment;
  final ep = CliEndpoint.resolve(
    os: Platform.isMacOS ? 'macos' : 'linux',
    env: env,
    home: env['HOME'] ?? '',
    uid: currentUid(),
  );
  final code = await runCli(
    argv,
    transport: UnixSocketTransport(),
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
