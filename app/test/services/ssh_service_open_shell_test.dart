import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
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
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final resizes = <(int, int)>[];

  @override
  bool get agentForwardingRefused => false;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  void write(Uint8List data) {}

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
}
