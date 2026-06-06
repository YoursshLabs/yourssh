// Diagnostic probe: connects to a target host THROUGH a jump host, reporting
// each layer separately so we can see exactly where it fails.
//
// Usage:
//   cd app
//   dart run tool/jump_probe.dart user@jumphost[:port] user@target[:port] \
//       [--jump-key /path/to/key] [--target-key /path/to/key]
//
// Prompts for passwords; pass --jump-key/--target-key to use private keys
// instead (passphrase prompted when the key is encrypted).

import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

({String user, String host, int port}) parse(String s) {
  final at = s.indexOf('@');
  if (at < 0) {
    stderr.writeln('Expected user@host[:port], got: $s');
    exit(2);
  }
  final user = s.substring(0, at);
  var rest = s.substring(at + 1);
  var port = 22;
  final colon = rest.lastIndexOf(':');
  if (colon > 0) {
    port = int.parse(rest.substring(colon + 1));
    rest = rest.substring(0, colon);
  }
  return (user: user, host: rest, port: port);
}

String ask(String prompt) {
  stdout.write(prompt);
  stdin.echoMode = false;
  final v = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();
  return v;
}

void step(String msg) => stdout.writeln('\n=== $msg ===');

List<SSHKeyPair>? loadKey(String path, String label) {
  final pem = File(path).readAsStringSync();
  if (SSHKeyPair.isEncryptedPem(pem)) {
    final pp = ask('Passphrase for $label key $path: ');
    return SSHKeyPair.fromPem(pem, pp);
  }
  return SSHKeyPair.fromPem(pem);
}

Future<void> main(List<String> args) async {
  final positional = <String>[];
  String? jumpKeyPath;
  String? targetKeyPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--jump-key':
        jumpKeyPath = args[++i];
      case '--target-key':
        targetKeyPath = args[++i];
      default:
        positional.add(args[i]);
    }
  }
  if (positional.length != 2) {
    stderr.writeln(
        'Usage: dart run tool/jump_probe.dart user@jump[:port] user@target[:port] '
        '[--jump-key path] [--target-key path]');
    exit(2);
  }
  final jump = parse(positional[0]);
  final target = parse(positional[1]);
  final jumpKeys = jumpKeyPath == null ? null : loadKey(jumpKeyPath, 'jump');
  final targetKeys =
      targetKeyPath == null ? null : loadKey(targetKeyPath, 'target');
  final jumpPw =
      jumpKeys != null ? '' : ask('Password for ${positional[0]}: ');
  final targetPw =
      targetKeys != null ? '' : ask('Password for ${positional[1]}: ');

  final sw = Stopwatch()..start();
  void t(String msg) => stdout.writeln('[${sw.elapsedMilliseconds}ms] $msg');

  // Layer 1: TCP to jump
  step('1) TCP connect to jump ${jump.host}:${jump.port}');
  final SSHSocket jumpSocket;
  try {
    jumpSocket = await SSHSocket.connect(jump.host, jump.port)
        .timeout(const Duration(seconds: 10));
    t('OK — TCP established');
  } catch (e) {
    t('FAIL — $e');
    exit(1);
  }

  // Layer 2: jump SSH auth
  step('2) SSH auth on jump as ${jump.user}');
  final jumpClient = SSHClient(
    jumpSocket,
    username: jump.user,
    identities: jumpKeys,
    onPasswordRequest: () => jumpPw,
    onVerifyHostKey: (_, _) async => true,
    printDebug: (m) => stdout.writeln('  [jump debug] $m'),
  );
  try {
    await jumpClient.authenticated.timeout(const Duration(seconds: 15));
    t('OK — jump authenticated');
  } catch (e) {
    t('FAIL — $e');
    exit(1);
  }

  // Layer 3: direct-tcpip channel through jump
  step('3) direct-tcpip channel to ${target.host}:${target.port}');
  final SSHForwardChannel channel;
  try {
    channel = await jumpClient
        .forwardLocal(target.host, target.port)
        .timeout(const Duration(seconds: 15));
    t('OK — channel open (jump allows TCP forwarding)');
  } catch (e) {
    t('FAIL — $e');
    t('Hint: if this is a channel-open failure, the jump sshd likely has '
        'AllowTcpForwarding no / restrictions for this user.');
    jumpClient.close();
    exit(1);
  }

  // Layer 4: inner SSH (KEX + auth) to target over the channel
  step('4) inner SSH to target as ${target.user} (KEX + auth over channel)');
  final targetClient = SSHClient(
    channel,
    username: target.user,
    identities: targetKeys,
    onPasswordRequest: () => targetPw,
    onVerifyHostKey: (_, _) async => true,
    printDebug: (m) => stdout.writeln('  [target debug] $m'),
  );
  try {
    await targetClient.authenticated.timeout(const Duration(seconds: 20));
    t('OK — target authenticated through jump');
  } catch (e) {
    t('FAIL — $e');
    targetClient.close();
    jumpClient.close();
    exit(1);
  }

  // Layer 5: run a command
  step('5) exec echo on target');
  try {
    final result = await targetClient
        .run('echo jump-ok from \$(hostname)')
        .timeout(const Duration(seconds: 10));
    t('OK — output: ${String.fromCharCodes(result).trim()}');
  } catch (e) {
    t('FAIL — $e');
  }

  targetClient.close();
  jumpClient.close();
  stdout.writeln('\nAll layers passed ✅');
  exit(0);
}
