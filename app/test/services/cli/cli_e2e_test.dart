import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh/services/cli/single_instance.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server_test.dart' show FakeHandlers;

class _NoLaunch implements AppLauncher {
  @override
  Future<void> launch(CliEndpoint ep) async =>
      fail('the app is running: the CLI must not launch it');
}

class _Sink extends StringBuffer implements IOSink {
  @override
  Encoding encoding = utf8;
  @override
  void add(List<int> data) => write(utf8.decode(data));
  @override
  void addError(Object error, [StackTrace? st]) {}
  @override
  Future addStream(Stream<List<int>> stream) async {}
  @override
  Future close() async {}
  @override
  Future get done async {}
  @override
  Future flush() async {}
  @override
  void writeln([Object? o = '']) => write('$o\n');
}

/// M8: the real `yourssh` client code (runCli + UnixSocketTransport + the
/// real token file) against the real app endpoint (lock + startCliEndpoint +
/// UnixCliListener + CliServer), in a temp HOME.
void main() {
  final skip = Platform.isWindows ? 'Unix socket endpoint' : null;
  late Directory home;

  setUp(() {
    // Short base path: the socket path must stay under 100 bytes.
    home = Directory('/tmp').createTempSync('yse2e');
  });
  tearDown(() => home.deleteSync(recursive: true));

  final hosts = [
    Host(id: 'a', label: 'web-1', host: 'w.example', username: 'root',
        tags: ['prod']),
    Host(id: 'b', label: 'db\x85', host: 'd.example', username: 'pg', port: 2222),
  ];

  for (final shared in [false, true]) {
    test('version and ls --json end to end (shared-temp run dir: $shared)',
        skip: skip, () async {
      final os = Platform.isMacOS ? 'macos' : 'linux';
      final ep = shared
          // The short fallback ($TMPDIR/yourssh-run): exercises the CLI's
          // owner/mode checks with the real /usr/bin/stat.
          ? CliEndpoint.resolve(
              os: 'macos', env: {'TMPDIR': home.path}, home: '/${'h' * 120}')
          : CliEndpoint.resolve(os: os, env: const {}, home: home.path);
      expect(ep.inSharedTemp, shared);

      final lock = await acquireInstanceLockOrForward(ep, const []);
      final owner = await startCliEndpoint(
          ep, CliServer(handlers: FakeHandlers(hosts), token: generateToken()),
          lock: lock!);
      addTearDown(owner.stop);

      Future<(int, String, String)> cli(List<String> argv) async {
        final out = _Sink(), err = _Sink();
        final code = await runCli(argv,
            transport: UnixSocketTransport(),
            launcher: _NoLaunch(),
            endpoint: ep,
            out: out,
            err: err,
            isTty: false,
            env: const {});
        return (code, out.toString(), err.toString());
      }

      final (vCode, vOut, vErr) = await cli(['version']);
      expect(vCode, 0, reason: vErr);
      expect(vOut, contains('yourssh CLI $kCliVersion'));
      expect(vOut, contains('YourSSH app 9.9.9 (protocol 1)'));

      final (lCode, lOut, lErr) = await cli(['ls', '--json']);
      expect(lCode, 0, reason: lErr);
      expect(lOut, isNot(contains('\x85')));
      expect(lOut, contains(r'\u0085'));
      final list = jsonDecode(lOut) as List;
      expect([for (final h in list) (h as Map)['label']], ['web-1', 'db\x85']);
      expect((list[1] as Map)['port'], 2222);
      for (final k in ['password', 'keyId', 'passphrase']) {
        expect(lOut, isNot(contains(k)));
      }
    });
  }
}
