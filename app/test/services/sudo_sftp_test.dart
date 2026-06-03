import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/sudo_sftp.dart';

/// Scripted fake backend. Each orchestrator effect is a closure over this.
class _Fake {
  /// stdout returned by the path probe exec.
  String probeStdout = '/usr/lib/openssh/sftp-server\n';

  /// Outcomes for successive openSftpExec calls. `true` → return a token
  /// client, `false` → throw (handshake failed / channel closed).
  List<bool> startOutcomes = [];

  /// Exit codes for successive validate (runExecWithStdin) calls.
  List<({String stderr, int exitCode})> validateOutcomes = [];

  /// Passwords returned per getPassword call (null = cancelled/missing).
  List<String?> passwords = [];

  /// stderr returned by runExec when the command is NOT the path probe
  /// (used by the custom-mode diagnostic re-exec).
  String diagStderr = '';

  final execLog = <String>[];
  final startLog = <({String command, Uint8List? preamble})>[];
  final validateStdin = <String>[];
  final passwordRequests = <({bool interactive, int attempt})>[];

  SudoSftpOrchestrator<String> orchestrator() => SudoSftpOrchestrator<String>(
        runExec: (cmd) async {
          execLog.add(cmd);
          if (cmd == buildPathProbeCommand()) {
            return (stdout: probeStdout, stderr: '', exitCode: 0);
          }
          return (stdout: '', stderr: diagStderr, exitCode: 1);
        },
        runExecWithStdin: (cmd, stdinData) async {
          execLog.add(cmd);
          validateStdin.add(utf8.decode(stdinData));
          return validateOutcomes.removeAt(0);
        },
        openSftpExec: (cmd, {stdinPreamble}) async {
          startLog.add((command: cmd, preamble: stdinPreamble));
          if (startOutcomes.removeAt(0)) return 'client';
          throw Exception('handshake failed');
        },
      );

  Future<String?> getPassword({
    required bool interactive,
    required int attempt,
  }) async {
    passwordRequests.add((interactive: interactive, attempt: attempt));
    return passwords.removeAt(0);
  }
}

Host _host(SftpMode mode, {String? command}) => Host(
      label: 's',
      host: 'h',
      username: 'u',
      sftpMode: mode,
      sftpServerCommand: command,
    );

void main() {
  group('pure helpers', () {
    test('path probe covers all known distro locations', () {
      final cmd = buildPathProbeCommand();
      for (final p in kSftpServerPaths) {
        expect(cmd, contains(p));
      }
    });

    test('classifySudoFailure', () {
      expect(classifySudoFailure('user is not in the sudoers file'),
          SudoSftpFailureReason.notInSudoers);
      expect(
          classifySudoFailure(
              'sudo: user is not allowed to execute /x as root'),
          SudoSftpFailureReason.notInSudoers);
      expect(classifySudoFailure('sudo: a terminal is required to read'),
          SudoSftpFailureReason.requiresTty);
      expect(
          classifySudoFailure('sudo: sorry, you must have a tty to run sudo'),
          SudoSftpFailureReason.requiresTty);
      expect(classifySudoFailure('sudo: 1 incorrect password attempt'),
          SudoSftpFailureReason.wrongPassword);
      expect(classifySudoFailure('Sorry, try again.'),
          SudoSftpFailureReason.wrongPassword);
      expect(classifySudoFailure('sh: sudo: command not found'),
          SudoSftpFailureReason.sudoNotInstalled);
      expect(classifySudoFailure('something else'), isNull);
    });
  });

  group('sudo mode', () {
    test('NOPASSWD: direct start succeeds, no password requested', () async {
      final fake = _Fake()..startOutcomes = [true];
      final client = await fake.orchestrator().openForHost(
            _host(SftpMode.sudo),
            getPassword: fake.getPassword,
            interactive: true,
          );
      expect(client, 'client');
      expect(fake.startLog.single.command,
          'LANG=C LC_ALL=C sudo -n /usr/lib/openssh/sftp-server');
      expect(fake.passwordRequests, isEmpty);
    });

    test('no binary found → binaryNotFound, no start attempted', () async {
      final fake = _Fake()..probeStdout = '\n';
      await expectLater(
        fake.orchestrator().openForHost(_host(SftpMode.sudo),
            getPassword: fake.getPassword, interactive: true),
        throwsA(isA<SudoSftpException>().having(
            (e) => e.reason, 'reason', SudoSftpFailureReason.binaryNotFound)),
      );
      expect(fake.startLog, isEmpty);
    });

    test('password flow: validate caches timestamp, retry succeeds', () async {
      final fake = _Fake()
        ..startOutcomes = [false, true]
        ..passwords = ['pw1']
        ..validateOutcomes = [(stderr: '', exitCode: 0)];
      final client = await fake.orchestrator().openForHost(
            _host(SftpMode.sudo),
            getPassword: fake.getPassword,
            interactive: true,
          );
      expect(client, 'client');
      expect(fake.validateStdin.single, 'pw1\n');
      expect(fake.execLog, contains("LANG=C LC_ALL=C sudo -S -p '' -v"));
      // Both starts used sudo -n; no inline password feeding needed.
      expect(fake.startLog.every((s) => s.preamble == null), isTrue);
    });

    test('timestamp_timeout=0: third start feeds validated password inline',
        () async {
      final fake = _Fake()
        ..startOutcomes = [false, false, true]
        ..passwords = ['pw1']
        ..validateOutcomes = [(stderr: '', exitCode: 0)];
      final client = await fake.orchestrator().openForHost(
            _host(SftpMode.sudo),
            getPassword: fake.getPassword,
            interactive: true,
          );
      expect(client, 'client');
      final last = fake.startLog.last;
      expect(last.command,
          "LANG=C LC_ALL=C sudo -S -p '' /usr/lib/openssh/sftp-server");
      expect(utf8.decode(last.preamble!), 'pw1\n');
    });

    test('wrong password, interactive → reprompts once (attempt 1)', () async {
      final fake = _Fake()
        ..startOutcomes = [false, true]
        ..passwords = ['bad', 'good']
        ..validateOutcomes = [
          (stderr: 'sudo: 1 incorrect password attempt', exitCode: 1),
          (stderr: '', exitCode: 0),
        ];
      await fake.orchestrator().openForHost(_host(SftpMode.sudo),
          getPassword: fake.getPassword, interactive: true);
      expect(fake.passwordRequests, [
        (interactive: true, attempt: 0),
        (interactive: true, attempt: 1),
      ]);
    });

    test('wrong password, non-interactive → fails without reprompt', () async {
      final fake = _Fake()
        ..startOutcomes = [false]
        ..passwords = ['bad']
        ..validateOutcomes = [
          (stderr: 'sudo: 1 incorrect password attempt', exitCode: 1),
        ];
      await expectLater(
        fake.orchestrator().openForHost(_host(SftpMode.sudo),
            getPassword: fake.getPassword, interactive: false),
        throwsA(isA<SudoSftpException>().having(
            (e) => e.reason, 'reason', SudoSftpFailureReason.wrongPassword)),
      );
      expect(fake.passwordRequests.length, 1);
    });

    test('not in sudoers → notInSudoers (no retry)', () async {
      final fake = _Fake()
        ..startOutcomes = [false]
        ..passwords = ['pw']
        ..validateOutcomes = [
          (stderr: 'user is not in the sudoers file.', exitCode: 1),
        ];
      await expectLater(
        fake.orchestrator().openForHost(_host(SftpMode.sudo),
            getPassword: fake.getPassword, interactive: true),
        throwsA(isA<SudoSftpException>().having(
            (e) => e.reason, 'reason', SudoSftpFailureReason.notInSudoers)),
      );
    });

    test('no password available, non-interactive → passwordRequired',
        () async {
      final fake = _Fake()
        ..startOutcomes = [false]
        ..passwords = [null];
      await expectLater(
        fake.orchestrator().openForHost(_host(SftpMode.sudo),
            getPassword: fake.getPassword, interactive: false),
        throwsA(isA<SudoSftpException>().having((e) => e.reason, 'reason',
            SudoSftpFailureReason.passwordRequired)),
      );
    });

    test('prompt cancelled, interactive → userCancelled', () async {
      final fake = _Fake()
        ..startOutcomes = [false]
        ..passwords = [null];
      await expectLater(
        fake.orchestrator().openForHost(_host(SftpMode.sudo),
            getPassword: fake.getPassword, interactive: true),
        throwsA(isA<SudoSftpException>().having(
            (e) => e.reason, 'reason', SudoSftpFailureReason.userCancelled)),
      );
    });
  });

  group('custom mode', () {
    test('runs the command verbatim, no path probe', () async {
      final fake = _Fake()..startOutcomes = [true];
      await fake.orchestrator().openForHost(
            _host(SftpMode.custom, command: 'doas /usr/lib/ssh/sftp-server'),
            getPassword: fake.getPassword,
            interactive: true,
          );
      expect(fake.startLog.single.command, 'doas /usr/lib/ssh/sftp-server');
      expect(fake.execLog, isEmpty); // no probe exec
    });

    test('missing command → commandMissing', () async {
      final fake = _Fake();
      await expectLater(
        fake.orchestrator().openForHost(_host(SftpMode.custom, command: '  '),
            getPassword: fake.getPassword, interactive: true),
        throwsA(isA<SudoSftpException>().having(
            (e) => e.reason, 'reason', SudoSftpFailureReason.commandMissing)),
      );
    });

    test('non-sudo command failure → handshakeFailed, no password flow',
        () async {
      final fake = _Fake()..startOutcomes = [false];
      await expectLater(
        fake.orchestrator().openForHost(
            _host(SftpMode.custom, command: 'doas /x'),
            getPassword: fake.getPassword,
            interactive: true),
        throwsA(isA<SudoSftpException>().having((e) => e.reason, 'reason',
            SudoSftpFailureReason.handshakeFailed)),
      );
      expect(fake.passwordRequests, isEmpty);
    });

    test('sudo command failure → validate then verbatim retry', () async {
      final fake = _Fake()
        ..startOutcomes = [false, true]
        ..passwords = ['pw']
        ..validateOutcomes = [(stderr: '', exitCode: 0)];
      await fake.orchestrator().openForHost(
            _host(SftpMode.custom, command: 'sudo -u deploy /x'),
            getPassword: fake.getPassword,
            interactive: true,
          );
      expect(fake.startLog.map((s) => s.command).toList(),
          ['sudo -u deploy /x', 'sudo -u deploy /x']);
    });

    test('sudo command: validate ok but retry fails → classifies diagnostic',
        () async {
      final fake = _Fake()
        ..startOutcomes = [false, false]
        ..passwords = ['pw']
        ..validateOutcomes = [(stderr: '', exitCode: 0)]
        ..diagStderr = 'user is not in the sudoers file.';
      await expectLater(
        fake.orchestrator().openForHost(
            _host(SftpMode.custom, command: 'sudo -u deploy /x'),
            getPassword: fake.getPassword,
            interactive: true),
        throwsA(isA<SudoSftpException>().having((e) => e.reason, 'reason',
            SudoSftpFailureReason.notInSudoers)),
      );
      expect(fake.execLog, contains('sudo -u deploy /x </dev/null'));
    });
  });

  group('normal mode', () {
    test('is rejected — orchestrator only handles elevated modes', () {
      final fake = _Fake();
      expect(
        () => fake.orchestrator().openForHost(_host(SftpMode.normal),
            getPassword: fake.getPassword, interactive: true),
        throwsArgumentError,
      );
    });
  });
}
