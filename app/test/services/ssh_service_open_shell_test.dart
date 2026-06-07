import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/agent_forwarding_state.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

/// Captures the PTY config passed to [shell] and hands back a scripted fake
/// session. Only the members [SshService.openShell] touches are implemented —
/// anything else falls through to [noSuchMethod] and fails loudly.
class _FakeClient implements SSHClient {
  _FakeClient(this._shell);

  final _FakeShell _shell;
  SSHPtyConfig? capturedPty;

  /// Runs inside [shell] before it returns — simulates events (e.g. a window
  /// resize) happening while the real network round-trip is in flight.
  void Function()? duringShellOpen;

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    capturedPty = pty;
    duringShellOpen?.call();
    return _shell;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShell implements SSHSession {
  _FakeShell({this.refused = false});

  final bool refused;
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final resizes = <(int, int)>[];

  @override
  bool get agentForwardingRefused => refused;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  final writes = <String>[];
  String get writtenText => writes.join();

  @override
  void write(Uint8List data) {
    writes.add(const Utf8Decoder().convert(data));
  }

  void emitStdout(String text) =>
      _stdout.add(Uint8List.fromList(const Utf8Encoder().convert(text)));

  @override
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {
    resizes.add((width, height));
  }

  @override
  Future<void> close() async {
    await _stdout.close();
    await _stderr.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('openShell opens the PTY at the terminal\'s current view size',
      () async {
    // Pins the 80x24 hardcode fix: the tab (and thus TerminalView layout)
    // exists before the SSH handshake finishes, so the terminal already has
    // its real dimensions — but onResize is only wired inside openShell, so
    // that early resize never reaches the remote. The PTY must be opened at
    // the terminal's current size, not a fixed 80x24 (which made remote
    // output wrap at half the window width).
    final svc = SshService(StorageService());
    final host =
        Host(label: 'fake', host: 'example.com', port: 22, username: 'u');
    final session = SshSession(host: host);
    session.terminal.resize(187, 43); // TerminalView laid out before connect

    final shell = _FakeShell();
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(client.capturedPty?.width, 187);
    expect(client.capturedPty?.height, 43);
    expect(client.capturedPty?.type, 'xterm-256color');

    await shell.close();
    await shellDone;
  });

  test('openShell syncs a resize that happened while the PTY was opening',
      () async {
    // The window can resize between reading the terminal size and wiring
    // onResize (the shell-open network round-trip). That resize fires while
    // onResize is still null and is otherwise lost — openShell must sync the
    // remote once after wiring the callback.
    final svc = SshService(StorageService());
    final host =
        Host(label: 'fake', host: 'example.com', port: 22, username: 'u');
    final session = SshSession(host: host);
    session.terminal.resize(187, 43);

    final shell = _FakeShell();
    final client = _FakeClient(shell)
      ..duringShellOpen = () => session.terminal.resize(120, 30);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(shell.resizes, contains((120, 30)));

    await shell.close();
    await shellDone;
  });

  test('openShell passes custom termType to SSHPtyConfig', () async {
    final svc = SshService(StorageService());
    final host =
        Host(label: 'fake', host: 'example.com', port: 22, username: 'u');
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final shell = _FakeShell();
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session, termType: 'vt100');
    await pumpEventQueue();

    expect(client.capturedPty?.type, 'vt100');

    await shell.close();
    await shellDone;
  });

  test('openShell fires a refused event when the server refuses forwarding',
      () async {
    final svc = SshService(StorageService());
    final host = Host(
        label: 'fake',
        host: 'example.com',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final events = <(String, String?, AgentForwardingState)>[];
    svc.onAgentForwardingEvent =
        (hostId, sessionId, state) => events.add((hostId, sessionId, state));

    final shell = _FakeShell(refused: true);
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(events, [(host.id, session.id, AgentForwardingState.refused)]);

    await shell.close();
    await shellDone;
  });

  test('openShell fires ready when forwarding is enabled and not refused '
      '(resets a stale refused on reconnect)', () async {
    final svc = SshService(StorageService());
    final host = Host(
        label: 'fake',
        host: 'example.com',
        port: 22,
        username: 'u',
        agentForwarding: true);
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final events = <(String, String?, AgentForwardingState)>[];
    svc.onAgentForwardingEvent =
        (hostId, sessionId, state) => events.add((hostId, sessionId, state));

    final shell = _FakeShell();
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(events, [(host.id, session.id, AgentForwardingState.ready)]);

    await shell.close();
    await shellDone;
  });

  // > 250 ms bracketed-paste settle timer inside openShell.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  group('session template injection', () {
    test('template-only host (SI off) injects cd/export without installer',
        () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          workingDir: '/srv/app',
          envVars: {'FOO': 'bar baz'});
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();

      shell.emitStdout('\x1b[?2004h\$ '); // line editor reading
      await settle();
      expect(shell.writtenText, contains('IFS= read -rs __ys'),
          reason: 'bootstrap must be written after readiness');

      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();
      expect(shell.writtenText, contains("cd -- '/srv/app' 2>/dev/null"));
      expect(shell.writtenText, contains("export FOO='bar baz'"));
      expect(shell.writtenText, isNot(contains('__yourssh_si')),
          reason: 'SI off → no installer in the payload');

      shell.emitStdout('echo-head __YS_DONE__\n');
      await pumpEventQueue();

      await shell.close();
      await shellDone;
    });

    test('SI on + template → payload has installer AND cd', () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          workingDir: '/srv/app');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();

      expect(shell.writtenText, contains('__yourssh_si'));
      expect(shell.writtenText, contains("cd -- '/srv/app'"));

      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();
      await shell.close();
      await shellDone;
    });

    test('no ShellIntegrationProvider wired → template host stays silent',
        () async {
      final svc = SshService(StorageService()); // no provider
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          workingDir: '/srv/app');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();

      expect(shell.writes, isEmpty);

      await shell.close();
      await shellDone;
    });

    test('startup snippet typed exactly once after DONE', () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();
      expect(shell.writes, isNot(contains('htop\n')),
          reason: 'snippet must wait for DONE');

      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();
      expect(shell.writes.where((w) => w == 'htop\n').length, 1);

      shell.emitStdout('regular output after handshake');
      await pumpEventQueue();
      expect(shell.writes.where((w) => w == 'htop\n').length, 1,
          reason: 'never re-sent');

      await shell.close();
      await shellDone;
    });

    test('non-bash fallback (DONE without RDY) still types the snippet',
        () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      final writesAfterBootstrap = shell.writes.length;

      // fish/other POSIX shells: bootstrap's `|| printf DONE` branch.
      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();

      expect(shell.writes.where((w) => w == 'htop\n').length, 1);
      // No RDY → payload was never sent: bootstrap + snippet only.
      expect(shell.writes.length, writesAfterBootstrap + 1);

      await shell.close();
      await shellDone;
    });

    test('tmux on → hidden setup runs, snippet skipped', () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          workingDir: '/srv/app',
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session, useTmux: true);
      await pumpEventQueue();
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();
      shell.emitStdout('__YS_RDY__');
      await pumpEventQueue();
      expect(shell.writtenText, contains("cd -- '/srv/app'"));

      shell.emitStdout('__YS_DONE__\n');
      await pumpEventQueue();
      expect(shell.writes, isNot(contains('htop\n')),
          reason: 'a tmux re-attach would replay the snippet — skip it');

      await shell.close();
      await shellDone;
    });

    test('user keystroke before handshake aborts setup AND snippet',
        () async {
      final svc = SshService(StorageService(),
          shellIntegration: ShellIntegrationProvider());
      final host = Host(
          label: 'f',
          host: 'e.com',
          username: 'u',
          shellIntegration: false,
          startupSnippet: 'htop');
      final session = SshSession(host: host);
      session.terminal.resize(80, 24);
      final shell = _FakeShell();
      svc.debugSetClient(host.id, _FakeClient(shell));

      final shellDone = svc.openShell(session);
      await pumpEventQueue();

      session.terminal.onOutput?.call('x'); // user typed first
      shell.emitStdout('\x1b[?2004h\$ ');
      await settle();

      expect(shell.writes, ['x'],
          reason: 'no bootstrap, no snippet — the user owns the session');

      await shell.close();
      await shellDone;
    });
  });

  test('openShell fires no event when the host has forwarding off', () async {
    final svc = SshService(StorageService());
    final host =
        Host(label: 'fake', host: 'example.com', port: 22, username: 'u');
    final session = SshSession(host: host);
    session.terminal.resize(80, 24);

    final events = <(String, String?, AgentForwardingState)>[];
    svc.onAgentForwardingEvent =
        (hostId, sessionId, state) => events.add((hostId, sessionId, state));

    final shell = _FakeShell();
    final client = _FakeClient(shell);
    svc.debugSetClient(host.id, client);

    final shellDone = svc.openShell(session);
    await pumpEventQueue();

    expect(events, isEmpty);

    await shell.close();
    await shellDone;
  });
}
