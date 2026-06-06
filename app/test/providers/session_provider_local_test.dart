import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/models/shell_profile.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/pty_runner.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _FakePty implements PtyRunner {
  final _output = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get output => _output.stream;
  @override
  void write(Uint8List data) {}
  @override
  void resize(int rows, int cols) {}
  @override
  void kill() => killed = true;
  @override
  Future<int> get exitCode => _exit.future;
}

Host _makeHost(String id) => Host(
      id: id, label: id, host: '$id.example.com', port: 22, username: 'user',
    );

SshSession _makeSsh(String hostId) => SshSession(host: _makeHost(hostId));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late SessionProvider p;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
    p = SessionProvider(SshService(StorageService()), TabMetadataService());
    p.localShell =
        LocalShellService(ptyFactory: (shell, args, c, r, env) => _FakePty());
  });

  tearDown(() {
    p.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  group('unified session list', () {
    test('assigning localShell wires shell-exit notifications to listeners',
        () async {
      final pty = _FakePty();
      final shell = LocalShellService(ptyFactory: (s, a, c, r, env) => pty);
      p.localShell = shell;
      await p.newLocalSession();

      var notified = false;
      p.addListener(() => notified = true);

      pty._exit.complete(0); // shell dies on its own (user typed `exit`)
      await Future<void>.delayed(Duration.zero);

      expect(notified, isTrue,
          reason: 'pane must rebuild into the "Restart shell" view');
    });

    test('newLocalSession adds a local session and makes it active', () async {
      await p.newLocalSession();
      expect(p.sessions, hasLength(1));
      expect(p.sessions.single, isA<LocalSession>());
      expect(p.activeSession, same(p.sessions.single));
    });

    test('activateNext cycles across SSH and local in tab order', () async {
      p.addWatchSession(_makeSsh('h1'));
      await p.newLocalSession();
      p.addWatchSession(_makeSsh('h2'));
      // order: [ssh h1, local, ssh h2]; active = ssh h2
      p.activateNext(); // wraps to h1
      expect(p.activeSession, same(p.sessions[0]));
      p.activateNext();
      expect(p.activeSession, isA<LocalSession>());
      p.activatePrev();
      expect(p.activeSession, same(p.sessions[0]));
    });

    test('closeSession on a local session removes it and clears active',
        () async {
      await p.newLocalSession();
      final id = p.sessions.single.id;
      p.closeSession(id);
      expect(p.sessions, isEmpty);
      expect(p.activeSession, isNull);
    });

    test('rename/color/pin work on local sessions without persisting',
        () async {
      await p.newLocalSession();
      p.addWatchSession(_makeSsh('h1'));
      final local = p.sessions.whereType<LocalSession>().single;
      p.renameSession(local.id, 'scratch');
      p.setSessionColor(local.id, '#ef4444');
      p.togglePin(local.id);
      expect(local.customLabel, 'scratch');
      expect(local.colorTag, '#ef4444');
      expect(local.isPinned, isTrue);
      expect(p.sessions.first, same(local)); // pinned moved to front
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('tab_meta_')), isEmpty);
    });

    test('sshSessions excludes locals; activeSshSession falls back', () async {
      final ssh = _makeSsh('h1');
      p.addWatchSession(ssh);
      await p.newLocalSession(); // local is now active
      expect(p.sshSessions, [ssh]);
      expect(p.activeSession, isA<LocalSession>());
      expect(p.activeSshSession, same(ssh));
    });

    test('activeSshSession is null when no SSH sessions exist', () async {
      await p.newLocalSession();
      expect(p.activeSshSession, isNull);
    });

    test('restartLocalSession resets exited status to running', () async {
      await p.newLocalSession();
      final local = p.sessions.whereType<LocalSession>().single;
      local.kill();
      expect(local.status, LocalSessionStatus.exited);
      await p.restartLocalSession(local.id);
      expect(local.status, LocalSessionStatus.running);
    });
  });

  group('shell picker', () {
    const gitBash = ShellProfile(
        id: 'git-bash', name: 'Git Bash', executable: 'bash.exe');

    test('newLocalSession resolves the default shell via the resolver',
        () async {
      String? gotShell;
      p.localShell = LocalShellService(ptyFactory: (shell, a, c, r, env) {
        gotShell = shell;
        return _FakePty();
      });
      p.defaultShellResolver = () => (profile: gitBash, dangling: false);
      await p.newLocalSession();
      expect(gotShell, 'bash.exe');
    });

    test('explicit profile bypasses the resolver', () async {
      String? gotShell;
      p.localShell = LocalShellService(ptyFactory: (shell, a, c, r, env) {
        gotShell = shell;
        return _FakePty();
      });
      var resolverCalled = false;
      p.defaultShellResolver = () {
        resolverCalled = true;
        return (profile: null, dangling: false);
      };
      await p.newLocalSession(profile: gitBash);
      expect(gotShell, 'bash.exe');
      expect(resolverCalled, false);
    });

    test('platformDefault bypasses the resolver', () async {
      var resolverCalled = false;
      p.defaultShellResolver = () {
        resolverCalled = true;
        return (profile: gitBash, dangling: false);
      };
      await p.newLocalSession(platformDefault: true);
      expect(resolverCalled, false);
      final session = p.sessions.whereType<LocalSession>().single;
      expect(session.profile, isNull);
    });

    test('dangling default writes a yellow warning into the terminal',
        () async {
      p.defaultShellResolver = () => (profile: null, dangling: true);
      await p.newLocalSession();
      final session = p.sessions.whereType<LocalSession>().single;
      expect(session.terminal.buffer.getText(),
          contains('Default shell not found'));
    });
  });
}
