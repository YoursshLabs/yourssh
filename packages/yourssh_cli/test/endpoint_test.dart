import 'dart:io';

import 'package:test/test.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

void main() {
  group('CliEndpoint.resolve', () {
    test('macos', () {
      final e = CliEndpoint.resolve(os: 'macos', env: {}, home: '/Users/a');
      expect(e.address,
          '/Users/a/Library/Application Support/YourSSH/run/cli.sock');
      expect(e.runDir, '/Users/a/Library/Application Support/YourSSH/run');
      expect(e.tokenPath,
          '/Users/a/Library/Application Support/YourSSH/run/cli.token');
    });
    test('linux with XDG_RUNTIME_DIR', () {
      final e = CliEndpoint.resolve(
          os: 'linux', env: {'XDG_RUNTIME_DIR': '/run/user/501'}, home: '/home/a');
      expect(e.address, '/run/user/501/yourssh/cli.sock');
      expect(e.tokenPath, '/run/user/501/yourssh/cli.token');
    });
    test('linux without XDG_RUNTIME_DIR', () {
      final e = CliEndpoint.resolve(os: 'linux', env: {}, home: '/home/a');
      expect(e.address, '/home/a/.local/state/yourssh/run/cli.sock');
    });
    test('linux with empty XDG_RUNTIME_DIR falls back', () {
      final e = CliEndpoint.resolve(
          os: 'linux', env: {'XDG_RUNTIME_DIR': ''}, home: '/home/a');
      expect(e.address, '/home/a/.local/state/yourssh/run/cli.sock');
    });
    test('windows', () {
      final e = CliEndpoint.resolve(
          os: 'windows',
          env: {'LOCALAPPDATA': r'C:\Users\a\AppData\Local'},
          home: r'C:\Users\a',
          userSid: 'S-1-5-21-1');
      expect(e.address, r'\\.\pipe\yourssh-cli-S-1-5-21-1');
    });
    test('windows without SID throws', () {
      expect(
          () => CliEndpoint.resolve(os: 'windows', env: {}, home: r'C:\Users\a'),
          throwsArgumentError);
    });
  });

  group('token file', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ys_cli_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('writeToken makes 64 hex chars with restrictive modes', () async {
      final run = '${tmp.path}/run';
      final tok = await writeToken(run);
      expect(tok, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await readToken('$run/cli.token'), tok);
      if (!Platform.isWindows) {
        expect(Directory(run).statSync().mode & 0x1ff, 0x1c0); // 0700
        expect(File('$run/cli.token').statSync().mode & 0x1ff, 0x180); // 0600
      }
    });
    test('rewrite yields a new token', () async {
      final run = '${tmp.path}/run';
      final a = await writeToken(run);
      final b = await writeToken(run);
      expect(a, isNot(b));
      expect(await readToken('$run/cli.token'), b);
    });
    test('readToken of missing file is null', () async {
      expect(await readToken('${tmp.path}/nope'), isNull);
    });
  });

  test('tokensEqual', () {
    expect(tokensEqual('ab', 'ab'), isTrue);
    expect(tokensEqual('ab', 'ac'), isFalse);
    expect(tokensEqual('ab', 'abc'), isFalse);
  });
}
