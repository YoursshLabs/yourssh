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
    final longHome = '/Users/${'x' * 60}';
    test('macos long home falls back to TMPDIR', () {
      final e = CliEndpoint.resolve(
          os: 'macos', env: {'TMPDIR': '/var/folders/ab/cd/T/'}, home: longHome);
      expect(e.address, '/var/folders/ab/cd/T/yourssh-run/cli.sock');
      expect(e.runDir, '/var/folders/ab/cd/T/yourssh-run');
      expect(e.tokenPath, '/var/folders/ab/cd/T/yourssh-run/cli.token');
      expect(e.inSharedTemp, isTrue);
    });
    test('linux long home falls back to /tmp/yourssh-<uid>', () {
      final e = CliEndpoint.resolve(
          os: 'linux', env: {}, home: '/home/${'x' * 90}', uid: 1000);
      expect(e.address, '/tmp/yourssh-1000/cli.sock');
      expect(e.tokenPath, '/tmp/yourssh-1000/cli.token');
      expect(e.inSharedTemp, isTrue);
    });
    test('normal paths are not flagged as shared temp', () {
      expect(
          CliEndpoint.resolve(os: 'macos', env: {}, home: '/Users/a')
              .inSharedTemp,
          isFalse);
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

  group('dev variant (non-release app builds; CLI with YOURSSH_DEV=1)', () {
    test('macos', () {
      final e = CliEndpoint.resolve(
          os: 'macos', env: {}, home: '/Users/a', dev: true);
      expect(e.runDir, '/Users/a/Library/Application Support/YourSSH-dev/run');
      expect(e.address,
          '/Users/a/Library/Application Support/YourSSH-dev/run/cli.sock');
      expect(e.tokenPath,
          '/Users/a/Library/Application Support/YourSSH-dev/run/cli.token');
    });
    test('macos long home falls back to TMPDIR/yourssh-dev-run', () {
      final e = CliEndpoint.resolve(
          os: 'macos',
          env: {'TMPDIR': '/var/folders/ab/cd/T/'},
          home: '/Users/${'x' * 60}',
          dev: true);
      expect(e.runDir, '/var/folders/ab/cd/T/yourssh-dev-run');
      expect(e.inSharedTemp, isTrue);
    });
    test('macos long home without TMPDIR falls back to /tmp/yourssh-dev-<uid>',
        () {
      final e = CliEndpoint.resolve(
          os: 'macos', env: {}, home: '/Users/${'x' * 60}', uid: 501, dev: true);
      expect(e.runDir, '/tmp/yourssh-dev-501');
      expect(e.inSharedTemp, isTrue);
    });
    test('linux with XDG_RUNTIME_DIR', () {
      final e = CliEndpoint.resolve(
          os: 'linux',
          env: {'XDG_RUNTIME_DIR': '/run/user/501'},
          home: '/home/a',
          dev: true);
      expect(e.address, '/run/user/501/yourssh-dev/cli.sock');
    });
    test('linux without XDG_RUNTIME_DIR', () {
      final e =
          CliEndpoint.resolve(os: 'linux', env: {}, home: '/home/a', dev: true);
      expect(e.address, '/home/a/.local/state/yourssh-dev/run/cli.sock');
    });
    test('linux long home falls back to /tmp/yourssh-dev-<uid>', () {
      final e = CliEndpoint.resolve(
          os: 'linux', env: {}, home: '/home/${'x' * 90}', uid: 1000, dev: true);
      expect(e.address, '/tmp/yourssh-dev-1000/cli.sock');
      expect(e.inSharedTemp, isTrue);
    });
    test('windows', () {
      final e = CliEndpoint.resolve(
          os: 'windows',
          env: {'LOCALAPPDATA': r'C:\Users\a\AppData\Local'},
          home: r'C:\Users\a',
          userSid: 'S-1-5-21-1',
          dev: true);
      expect(e.runDir, r'C:\Users\a\AppData\Local\YourSSH-dev\run');
      expect(e.tokenPath, r'C:\Users\a\AppData\Local\YourSSH-dev\run\cli.token');
      expect(e.address, r'\\.\pipe\yourssh-cli-dev-S-1-5-21-1');
    });
    test('release and dev never share a path on any OS', () {
      for (final os in ['macos', 'linux', 'windows']) {
        CliEndpoint r(bool dev) => CliEndpoint.resolve(
            os: os,
            env: const {},
            home: os == 'windows' ? r'C:\Users\a' : '/home/a',
            userSid: 'S-1-5-21-1',
            uid: 1,
            dev: dev);
        expect(r(true).runDir, isNot(r(false).runDir), reason: os);
        expect(r(true).address, isNot(r(false).address), reason: os);
      }
    });
  });

  group('CliEndpoint.forCli (the yourssh binary)', () {
    test('YOURSSH_DEV=1 selects the dev variant on every OS', () {
      expect(
          CliEndpoint.forCli(
                  os: 'macos', env: {'HOME': '/Users/a', 'YOURSSH_DEV': '1'})
              .runDir,
          '/Users/a/Library/Application Support/YourSSH-dev/run');
      expect(
          CliEndpoint.forCli(
              os: 'linux',
              env: {'HOME': '/home/a', 'YOURSSH_DEV': '1'},
              uid: 7).address,
          '/home/a/.local/state/yourssh-dev/run/cli.sock');
      expect(
          CliEndpoint.forCli(
              os: 'windows',
              env: {
                'USERPROFILE': r'C:\Users\a',
                'LOCALAPPDATA': r'C:\L',
                'YOURSSH_DEV': '1'
              },
              userSid: 'S-1-5-21-1').address,
          r'\\.\pipe\yourssh-cli-dev-S-1-5-21-1');
    });
    test('unset or any other value selects the release endpoint', () {
      for (final v in [null, '', '0', 'true', 'yes']) {
        final env = {'HOME': '/Users/a', if (v != null) 'YOURSSH_DEV': v};
        expect(CliEndpoint.forCli(os: 'macos', env: env).runDir,
            '/Users/a/Library/Application Support/YourSSH/run',
            reason: '$v');
      }
      expect(
          CliEndpoint.forCli(
              os: 'windows',
              env: {'USERPROFILE': r'C:\Users\a'},
              userSid: 'S-1-5-21-1').runDir,
          r'C:\Users\a\AppData\Local\YourSSH\run');
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
